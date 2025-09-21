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
        "1.20.11-00" = "1.20.11-do.0"
        "1.24.4-00" = "1.24.4-do.0"
        "1.33.1-00" = "1.33.1-do.3"
    }
    last_kube_do_version = reverse(values(local.kube_do_matrix))[0]
    kube_major_minor = regex("^[0-9]+.[0-9]+", var.config.packer_config.kubernetes_version)
    kube_versions_found = [
        for KUBE_V, DO_KUBE_V in local.kube_do_matrix: DO_KUBE_V
        if length(regexall("^${local.kube_major_minor}", KUBE_V)) > 0
    ]
    do_kubernetes_version = (lookup(local.kube_do_matrix, var.config.packer_config.kubernetes_version, null) != null
        ? local.kube_do_matrix[var.config.packer_config.kubernetes_version]
        : (length(local.kube_versions_found) > 0
            ? reverse(local.kube_versions_found)[0]
            : local.last_kube_do_version) )

    cluster_services = {
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
    }
    tf_helm_values = {
        nginx = <<-EOF
        controller:
          service:
            annotations:
              service.beta.kubernetes.io/do-loadbalancer-name: "${var.config.server_name_prefix}-${var.config.region}-cluster"
              service.beta.kubernetes.io/do-loadbalancer-protocol: "*"
        EOF
              #service.beta.kubernetes.io/do-loadbalancer-protocol: "http"
              #service.beta.kubernetes.io/do-loadbalancer-http-ports: "80"
              #service.beta.kubernetes.io/do-loadbalancer-tls-ports: "443"
              #service.beta.kubernetes.io/do-loadbalancer-redirect-http-to-https: "true"
              #service.beta.kubernetes.io/do-loadbalancer-protocol: "https"
        certmanager = <<-EOF
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

    ##TODO: Test support for count AND/OR autoscale
    dynamic "node_pool" {
        for_each = {
            for ind, obj in var.config.managed_kubernetes_conf: ind => ind
            if lookup(obj, "count", 0) > 0
        }
        content {
            name       = "${var.config.server_name_prefix}-${var.config.region}-kubeworker"
            size       = var.config.managed_kubernetes_conf[node_pool.key].size
            node_count = var.config.managed_kubernetes_conf[node_pool.key].count
            tags = [ "${replace(local.kubernetes, ".", "-")}" ]
        }
    }

    dynamic "node_pool" {
        for_each = {
            for ind, obj in var.config.managed_kubernetes_conf: ind => ind
            if lookup(obj, "min_nodes", 0) > 0 && lookup(obj, "max_nodes", 0) > 0
        }
        content {
            name       = "${var.config.server_name_prefix}-${var.config.region}-kubeworker"
            size       = var.config.managed_kubernetes_conf[node_pool.key].size
            min_nodes  = var.config.managed_kubernetes_conf[node_pool.key].min_nodes
            max_nodes  = var.config.managed_kubernetes_conf[node_pool.key].max_nodes
            auto_scale  = var.config.managed_kubernetes_conf[node_pool.key].auto_scale
            tags = [ "${replace(local.kubernetes, ".", "-")}" ]
        }

    }
}

resource "helm_release" "cluster_services" {
    for_each = {
        for servicename, service in local.cluster_services:
        servicename => service
        if service.enabled
    }
    name             = each.key
    chart            = each.value.chart
    namespace        = each.value.namespace != "" ? each.value.namespace : "default"
    create_namespace = each.value.create_namespace
    repository       = each.value.chart_url
    version          = each.value.chart_version != "" ? each.value.chart_version : ""
    dependency_update = true
    values           = concat(
        [for f in each.value.opt_value_files: file("${path.module}/helm_values/${f}")],
        [for key, values in local.tf_helm_values: values if key == each.key]
    )
}

## Comes from nginx helm_release cluster_service
data "digitalocean_loadbalancer" "main" {
    depends_on = [
        digitalocean_kubernetes_cluster.main,
        helm_release.cluster_services["nginx"]
    ]
    name = digitalocean_kubernetes_cluster.main.name
}

resource "kubectl_manifest" "buildkitd" {
    for_each = local.buildkit_files
    depends_on = [
        digitalocean_kubernetes_cluster.main,
    ]
    yaml_body = each.value
}
