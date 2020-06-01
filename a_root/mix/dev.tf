
module "dev_provisioners" {
    source      = "../../provisioners"
    servers     = var.dev_servers
    names       = var.dev_names
    public_ips  = var.dev_public_ips
    private_ips = var.dev_private_ips
    region      = var.region

    aws_bot_access_key = var.aws_bot_access_key
    aws_bot_secret_key = var.aws_bot_secret_key

    deploy_key_location = var.deploy_key_location

    docker_compose_version = var.docker_compose_version
    docker_engine_install_url  = var.docker_engine_install_url
    consul_version         = var.consul_version

    # Concating list is solution to element not allowing empty lists regardless of conditional
    # https://github.com/hashicorp/terraform/issues/11210
    docker_leader_name = (length(var.lead_names) > 0
        ? element(concat(var.lead_names, [""]), 0)
        : "")

    consul_lan_leader_ip = (length(var.admin_public_ips) > 0
        ? element(concat(var.admin_public_ips, [""]), var.admin_servers - 1)
        : element(concat(var.lead_public_ips, [""]), 0))

    role = "web"
    joinSwarm = false
    installCompose = true
}
