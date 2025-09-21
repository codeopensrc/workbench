terraform {
    required_providers {
        helm = {
            source = "hashicorp/helm"
        }
    }
}

provider "helm" {
    kubernetes = {
        host  = module.cloud.cluster_info.endpoint
        token = module.cloud.cluster_info.kube_config.token
        cluster_ca_certificate = base64decode(
            module.cloud.cluster_info.kube_config.cluster_ca_certificate
        )
    }
    experiments = {
        manifest = var.helm_experiments && fileexists("${path.module}/${terraform.workspace}-kube_config")
    }
}
