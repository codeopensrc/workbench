output "cluster_info" {
    value = {
        endpoint  = digitalocean_kubernetes_cluster.main.endpoint
        kube_config = digitalocean_kubernetes_cluster.main.kube_config[0]
    }
}

data "digitalocean_spaces_bucket_object" "gitlab_secrets" {
    provider = digitalocean.spaces
    count = (var.config.gitlab_enabled && var.config.import_gitlab 
        && var.config.gitlab_secrets.key != "" && var.config.gitlab_secrets.bucket != "" ? 1 : 0)
    bucket = var.config.gitlab_secrets.bucket != "" ? var.config.gitlab_secrets.bucket : "${var.config.env_bucket_prefix}-backups"
    region = var.config.do_region
    key    = var.config.gitlab_secrets.key != "" ? var.config.gitlab_secrets.key : ""
}

output "gitlab_secrets_body" {
    value = length(data.digitalocean_spaces_bucket_object.gitlab_secrets) > 0 ? data.digitalocean_spaces_bucket_object.gitlab_secrets[0].body : ""
}
