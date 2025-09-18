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
}



##! To save a copy of the kubeconfig locally
##! Must be authenticated to use `doctl kubernetes` command
#`doctl auth init`
#`doctl kubernetes cluster list`; `doctl kubernetes cluster kubeconfig save <cluster name>`
resource "digitalocean_kubernetes_cluster" "main" {
    count = contains(var.config.container_orchestrators, "managed_kubernetes") ? 1 : 0
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

resource "null_resource" "provision_kubeconfig" {
    for_each = {
        for key, cfg in digitalocean_droplet.main: key => cfg
        if contains(var.config.container_orchestrators, "managed_kubernetes")
            && (contains(cfg.tags, "admin") || contains(cfg.tags, "lead"))
    }
    provisioner "remote-exec" {
        inline = [ "mkdir -p /root/.kube" ]
    }
    provisioner "file" {
        content = nonsensitive(digitalocean_kubernetes_cluster.main[0].kube_config[0].raw_config)
        destination = "/root/.kube/config"
    }
    ## We were patching the deployment, but converting to a daemonset suits us better currently
    provisioner "file" {
        #"kubectl patch deployment -n ingress-nginx ingress-nginx-controller --type merge --patch \"$(cat /root/.kube/ingress-controller-deploy-patch.yml)\"",
        content = <<-EOF
        spec:
          template:
            spec:
              affinity:
                podAntiAffinity:                                  
                  preferredDuringSchedulingIgnoredDuringExecution:
                  - podAffinityTerm:                              
                      labelSelector:
                        matchExpressions:                         
                        - key: app.kubernetes.io/name
                          operator: In                            
                          values:
                          - ingress-nginx                         
                      topologyKey: kubernetes.io/hostname         
                    weight: 100                                   
        EOF
        destination = "/root/.kube/ingress-controller-deploy-patch.yml"
    }

    ### External LB http ports -> Kubernetes LB nodeport service ports
    ### This ensures the terraform load balancer and nginx controller nodeports match
    ### We do this with sed initially but upload the patch for backup
    provisioner "file" {
        #"kubectl patch service -n ingress-nginx ingress-nginx-controller --type merge --patch \"$(cat /root/.kube/ingress-controller-svc-patch.yml)\"",
        content = <<-EOF
        spec:
          ports:
            - name: http
              port: 80
              protocol: TCP
              targetPort: http
              nodePort: ${local.lb_http_nodeport}
              appProtocol: http            
            - name: https
              port: 443
              protocol: TCP
              targetPort: https
              nodePort: ${local.lb_https_nodeport}
              appProtocol: https
        EOF
        destination = "/root/.kube/ingress-controller-svc-patch.yml"
    }

    ### Cert redirection service and ingress
    ### Other ingresses should have a path from "/.well-known" to cert-redirect service
    ### app.domain/.well-known -> cert-redirect:80 -> cert.domain:cert_port
    provisioner "file" {
        content = <<-EOF
        apiVersion: v1
        kind: Service
        metadata:
          name: cert-redirect
          namespace: default
        spec:
          type: ExternalName
          externalName: cert.${var.config.root_domain_name}
          ports:
          - port: ${var.config.cert_port}
        ---
        apiVersion: networking.k8s.io/v1
        kind: Ingress
        metadata:
          name: ingress-cert-redirect
        spec:
          ingressClassName: nginx
          rules:
          - http:
              paths:
              - path: "/.well-known"                                   
                pathType: Prefix
                backend:
                  service:
                    name: cert-redirect
                    port:
                      number: 80
        EOF
        destination = "/root/.kube/ingress-letsencrypt.yml"
    }

    ## Example patch: Apply after we obtain and add a tls secret
    #provisioner "file" {
    #    content = <<-EOF
    #    metadata:
    #      annotations:
    #        service.beta.kubernetes.io/do-loadbalancer-redirect-http-to-https: "true"
    #        service.beta.kubernetes.io/do-loadbalancer-protocol: "https"
    #    EOF
    #    destination = "/root/.kube/lb-svc-patch.yml"
    #}

    connection {
        host = each.value.ipv4_address
        type = "ssh"
    }
}


resource "null_resource" "configure_ingress_controller" {
    count = contains(var.config.container_orchestrators, "managed_kubernetes") ? 1 : 0
    depends_on = [ null_resource.provision_kubeconfig ]

    ###! NOTE: Attaches/configures the cloud load balancer to kubernetes LoadBalancer service with its id
    ## https://docs.digitalocean.com/products/kubernetes/how-to/add-load-balancers/
    provisioner "remote-exec" {
        inline = [
            "wget -O /root/.kube/ingress-nginx-controller.yml https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.1.0/deploy/static/provider/do/deploy.yaml",
            "sed -i '/.*do-loadbalancer.*/a\\    kubernetes.digitalocean.com/load-balancer-id: \"${digitalocean_loadbalancer.main[0].id}\"' /root/.kube/ingress-nginx-controller.yml",
            "sed -i '/.*do-loadbalancer.*/a\\    service.beta.kubernetes.io/do-loadbalancer-name: \"${local.lb_name}\"' /root/.kube/ingress-nginx-controller.yml",
            "sed -i '/.*targetPort: http$/a\\      nodePort: ${local.lb_http_nodeport}' /root/.kube/ingress-nginx-controller.yml",
            "sed -i '/.*targetPort: https$/a\\      nodePort: ${local.lb_https_nodeport}' /root/.kube/ingress-nginx-controller.yml",
            "sed -i 's/kind: Deployment/kind: DaemonSet/' /root/.kube/ingress-nginx-controller.yml",
            "kubectl apply -f /root/.kube/ingress-nginx-controller.yml",
            "echo 'Wait 60 for Nginx ingress controller'",
            "sleep 60", ## ingress-letsencrypt.yml uses `ingressClassName: nginx` - controller needs to be up to accept ingress webhook validation
            "kubectl apply -f /root/.kube/ingress-letsencrypt.yml",
            "kubectl delete pod -n ingress-nginx -l 'app.kubernetes.io/component=admission-webhook'"
        ]
    }
    provisioner "remote-exec" {
        inline = [
            "git clone https://gitlab.codeopensrc.com/kc/website.git repos/website",
            "git clone https://gitlab.codeopensrc.com/os/react-template.git repos/react-template",
            "cp repos/website/.env.tmpl repos/website/.env",
            "cp repos/react-template/.env.tmpl repos/react-template/.env",
            "(cd repos/website/ && bash kube-deploy.sh -n default -h 10.10.0.2)",
            "(cd repos/react-template && bash kube-deploy.sh -n default -h 10.10.0.2)",
        ]
    }
    connection {
        host = [
            for h in digitalocean_droplet.main: h.ipv4_address
            if (contains(h.tags, "admin") || contains(h.tags, "lead"))
        ][0]
        type = "ssh"
    }
}
