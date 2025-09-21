terraform {
    required_providers {
        digitalocean = {
            source = "digitalocean/digitalocean"
        }
        kubectl = {
            source = "gavinbunney/kubectl"
            version = "1.19.0"
        }
        helm = {
            source = "hashicorp/helm"
        }
    }
    required_version = ">=0.13"
}

provider "digitalocean" {
    token = var.config.do_token
}

provider "kubectl" {
    host  = digitalocean_kubernetes_cluster.main.endpoint
    token = digitalocean_kubernetes_cluster.main.kube_config[0].token
    cluster_ca_certificate = base64decode(
        digitalocean_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate
    )
    load_config_file = false
}

provider "helm" {
    kubernetes = {
        host  = digitalocean_kubernetes_cluster.main.endpoint
        token = digitalocean_kubernetes_cluster.main.kube_config[0].token
        cluster_ca_certificate = base64decode(
            digitalocean_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate
        )
    }
    experiments = {
        manifest = var.config.helm_experiments
    }
}
