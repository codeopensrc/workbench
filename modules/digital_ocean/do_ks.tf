locals {
    ###! `doctl kubernetes options versions`
    ###! As of 11/24/2022
    #Slug            Kubernetes Version    Supported Features
    #1.24.4-do.0     1.24.4                cluster-autoscaler, docr-integration, ha-control-plane, token-authentication
    #1.23.10-do.0    1.23.10               cluster-autoscaler, docr-integration, ha-control-plane, token-authentication

    ###! As of 1/3/2022
    #Slug            Kubernetes Version    Supported Features
    #1.21.5-do.0     1.21.5                cluster-autoscaler, docr-integration, ha-control-plane, token-authentication
    #1.20.11-do.0    1.20.11               cluster-autoscaler, docr-integration, token-authentication
    #1.19.15-do.0    1.19.15               cluster-autoscaler, docr-integration, token-authentication
    
    kube_do_matrix = {
        "1.33.1-00" = "1.33.1-do.4"
    }
    last_kube_do_version = reverse(values(local.kube_do_matrix))[0]
    kube_major_minor = regex("^[0-9]+.[0-9]+", var.config.kubernetes_version)
    kube_versions_found = [
        for KUBE_V, DO_KUBE_V in local.kube_do_matrix: DO_KUBE_V
        if length(regexall("^${local.kube_major_minor}", KUBE_V)) > 0
    ]
    do_kubernetes_version = (lookup(local.kube_do_matrix, var.config.kubernetes_version, null) != null
        ? local.kube_do_matrix[var.config.kubernetes_version]
        : (length(local.kube_versions_found) > 0
            ? reverse(local.kube_versions_found)[0]
            : local.last_kube_do_version) )

    ## TODO: togglable outside module
    cluster_services = {
        buildkitd = {
            "enabled"         = true
        }
        nginx = {
            "enabled"          = true
            "chart"            = "ingress-nginx"
            "namespace"        = "ingress-nginx"
            "create_namespace" = true
            "chart_url"        = "https://kubernetes.github.io/ingress-nginx"
            "chart_version"    = "4.13.2"
            "opt_value_files"  = ["nginx-values.yml"]
        }
        certmanager = {
            "enabled"          = true
            "chart"            = "cert-manager"
            "namespace"        = "cert-manager"
            "create_namespace" = true
            "chart_url"        = "https://charts.jetstack.io"
            "chart_version"    = "v1.18.2"
            "opt_value_files"  = []
        }
    }
    additional_services = {}
    certmanager_files = {
        for ind, issuer in 
        split("---", templatefile("${path.module}/helm_values/certissuers.yml", { contact_email = var.config.contact_email })) :
        ["staging", "prod"][ind] => trimspace(issuer)
    }

    buildkit_files = {
        for ind, file in 
        split("---", templatefile("${path.module}/manifests/buildkitd.yaml", 
            { buildkitd_version = var.config.buildkitd_version
            buildkitd_namespace = var.config.buildkitd_namespace }
        )) :
        ["namespace", "statefulset"][ind] => trimspace(file)
        if local.cluster_services.buildkitd.enabled
    }
    tf_helm_values = {
        #--set controller.wildcardTLS.cert=ingress-nginx/example-com-certificate
        nginx = <<-EOF
        controller:
          nodeSelector:
            type: main
          tolerations:
            - key: "type"
              operator: "Equal"
              value: "main"
              effect: "NoSchedule"
          service:
            annotations:
              service.beta.kubernetes.io/do-loadbalancer-name: "${var.config.server_name_prefix}-${var.config.region}-cluster"
              service.beta.kubernetes.io/do-loadbalancer-protocol: "*"
        tcp:
          22: "gitlab/gitlab-gitlab-shell:22"
        EOF
              #service.beta.kubernetes.io/do-loadbalancer-protocol: "http"
              #service.beta.kubernetes.io/do-loadbalancer-http-ports: "80"
              #service.beta.kubernetes.io/do-loadbalancer-tls-ports: "443"
              #service.beta.kubernetes.io/do-loadbalancer-redirect-http-to-https: "true"
              #service.beta.kubernetes.io/do-loadbalancer-protocol: "https"
        certmanager = <<-EOF
        nodeSelector:
          type: main
        tolerations:
          - key: "type"
            operator: "Equal"
            value: "main"
            effect: "NoSchedule"
        cainjector:
          nodeSelector:
            type: main
          tolerations:
            - key: "type"
              operator: "Equal"
              value: "main"
              effect: "NoSchedule"
        webhook:
          nodeSelector:
            type: main
          tolerations:
            - key: "type"
              operator: "Equal"
              value: "main"
              effect: "NoSchedule"
        crds:
          enabled: true
        extraObjects:
        - |
          ${indent(2, local.certmanager_files["staging"])}
        - |
          ${indent(2, local.certmanager_files["prod"])}
        EOF
    }
}



##! Another way to save a copy of the kubeconfig locally
##! Must be authenticated to use `doctl kubernetes` command
#`doctl auth init`
#`doctl kubernetes cluster list`; `doctl kubernetes cluster kubeconfig save <cluster name>`
resource "digitalocean_kubernetes_cluster" "main" {
    name     = "${var.config.server_name_prefix}-${var.config.region}-cluster"
    region  = var.config.region
    version = local.do_kubernetes_version
    vpc_uuid = digitalocean_vpc.terraform_vpc.id

    cluster_autoscaler_configuration {
        scale_down_unneeded_time = "5m"
    }

    ##TODO: Test support for count AND/OR autoscale
    dynamic "node_pool" {
        for_each = {
            for ind, obj in var.config.managed_kubernetes_conf: ind => obj
            if ind == 0 && lookup(obj, "count", 0) > 0
        }
        content {
            name       = "${var.config.server_name_prefix}-main-${replace(lookup(node_pool.value, "key", substr(node_pool.value.size, -3, -1)), "main-", "")}"
            size       = node_pool.value.size
            node_count = node_pool.value.count
            tags = [ ]
            ## TODO: Support multiple labels
            labels = {
                type  = lookup(node_pool.value, "label", null)
            }

            dynamic "taint" {
                for_each = {
                    for val in lookup(node_pool.value, "taints", []): val => val
                }
                content {
                    key = "type"
                    value = taint.value
                    effect = "NoSchedule"
                }
            }
        }
    }

    dynamic "node_pool" {
        for_each = {
            for ind, obj in var.config.managed_kubernetes_conf: ind => obj
            if ind == 0 && lookup(obj, "auto_scale", false) && lookup(obj, "min_nodes", 0) > 0
        }
        content {
            name       = "${var.config.server_name_prefix}-main-${replace(lookup(node_pool.value, "key", substr(node_pool.value.size, -3, -1)), "main-", "")}"
            size       = node_pool.value.size
            min_nodes  = node_pool.value.min_nodes
            max_nodes  = node_pool.value.max_nodes
            auto_scale  = node_pool.value.auto_scale
            tags = [ ]
            ## TODO: Support multiple labels
            labels = {
                type  = lookup(node_pool.value, "label", null)
            }

            dynamic "taint" {
                for_each = {
                    for val in lookup(node_pool.value, "taints", []): val => val
                }
                content {
                    key = "type"
                    value = taint.value
                    effect = "NoSchedule"
                }
            }
        }

    }
}

resource "digitalocean_kubernetes_node_pool" "extra" {
    for_each = {
        for ind, obj in var.config.managed_kubernetes_conf: "${lookup(obj, "key", substr(obj.size, -3, -1))}" => obj
        if ind > 0 && (lookup(obj, "count", 0) > 0 || lookup(obj, "auto_scale", false))
    }
    cluster_id = digitalocean_kubernetes_cluster.main.id

    name       = "${var.config.server_name_prefix}-${each.key}"
    size       = each.value.size
    tags       = [ ]

    node_count = lookup(each.value, "count", 0) > 0 ? each.value.count : null
    ## node_count OR auto_scale
    auto_scale  = lookup(each.value, "auto_scale", null)
    min_nodes  = lookup(each.value, "min_nodes", -1) > -1 ? each.value.min_nodes : null
    max_nodes  = lookup(each.value, "max_nodes", 0) > 0 ? each.value.max_nodes : null

    labels = {
        for key, value in lookup(each.value, "labels", {}):
        key => value
    }

    dynamic "taint" {
        for_each = {
            for key, value in lookup(each.value, "taints", {}): 
            key => value
        }
        content {
            key = taint.key
            value = taint.value
            effect = "NoSchedule"
        }
    }
}

resource "helm_release" "cluster_services" {
    for_each = {
        for servicename, service in local.cluster_services:
        servicename => service
        if service.enabled && lookup(service, "chart", "") != ""
    }
    name              = each.key
    chart             = each.value.chart
    namespace         = lookup(each.value, "namespace", "default")
    create_namespace  = each.value.create_namespace
    repository        = each.value.chart_url
    version           = lookup(each.value, "chart_version", null)
    timeout           = 300
    force_update      = true
    recreate_pods     = false
    dependency_update = true
    wait              = lookup(each.value, "wait", true)
    replace           = lookup(each.value, "replace", false)
    values            = concat(
        [for f in each.value.opt_value_files: file("${path.module}/helm_values/${f}")],
        [for key, values in local.tf_helm_values: values if key == each.key]
    )
}

resource "helm_release" "additional_services" {
    for_each = {
        for servicename, service in local.additional_services:
        servicename => service
        if service.enabled && lookup(service, "chart", "") != ""
    }
    depends_on = [
        helm_release.cluster_services
    ]
    name              = each.key
    chart             = each.value.chart
    namespace         = lookup(each.value, "namespace", "default")
    create_namespace  = each.value.create_namespace
    repository        = each.value.chart_url
    version           = lookup(each.value, "chart_version", null)
    timeout           = 300
    force_update      = true
    recreate_pods     = false
    dependency_update = true
    wait              = lookup(each.value, "wait", true)
    replace           = lookup(each.value, "replace", false)
    values            = concat(
        [for f in each.value.opt_value_files: file("${path.module}/helm_values/${f}")],
        [for key, values in local.tf_helm_values: values if key == each.key]
    )
}

## Comes from nginx helm_release cluster_service
data "digitalocean_loadbalancer" "main" {
    depends_on = [
        helm_release.cluster_services["nginx"]
    ]
    name = "${var.config.server_name_prefix}-${var.config.region}-cluster"
}

resource "kubectl_manifest" "buildkitd" {
    for_each = local.buildkit_files
    depends_on = [
        digitalocean_kubernetes_cluster.main,
    ]
    yaml_body = each.value
}
