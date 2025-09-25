terraform {
    required_providers {
        helm = {
            source = "hashicorp/helm"
        }
        gitlab = {
            source = "gitlabhq/gitlab"
            version = "18.4.1"
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

provider "gitlab" {
    token    = module.gitlab.gitlab_pat
    base_url = "https://gitlab.${var.root_domain_name}"
}
