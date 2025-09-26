terraform {
    required_providers {
        helm = {
            source = "hashicorp/helm"
        }
        gitlab = {
            source = "gitlabhq/gitlab"
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
        manifest = var.helm_experiments && fileexists(local.kubeconfig_path)
    }
}

## TODO: How do we not use the gitlab provider if deploying gitlab helm chart disabled
provider "gitlab" {
    #https://gitlab.com/gitlab-org/api/client-go#use-the-config-package-experimental
    #config_file = ""
    early_auth_check = false
    token    = module.gitlab.gitlab_pat
    base_url = "https://gitlab.${local.root_domain_name}/api/v4"
}
