terraform {
    required_providers {
        digitalocean = {
            source = "digitalocean/digitalocean"
        }
    }
    required_version = ">=0.13"
}

# variable "root_domain_name" {}
# variable "local_ssh_key_file" {}
# variable "active_env_provider" {}
# variable "server_name_prefix" {}
# variable "region" { default = "" }
# variable "aws_key_name" {}
# variable "packer_image_id" { default = "" }
# variable "servers" { default = [] }
# variable "downsize" { default = false }
# variable "stun_port" { default = "" }
# variable "docker_machine_ip" { default = "" }
# variable "admin_arecord_aliases" { type = list }
# variable "db_arecord_aliases" { type = list }
# variable "leader_arecord_aliases" { type = list }
# variable "offsite_arecord_aliases" { type = list }
# variable "additional_domains" { type = map }
# variable "app_definitions" {
#     type = map(object({ pull=string, stable_version=string, use_stable=string,
#         repo_url=string, repo_name=string, docker_registry=string, docker_registry_image=string,
#         docker_registry_url=string, docker_registry_user=string, docker_registry_pw=string, service_name=string,
#         green_service=string, blue_service=string, default_active=string,
#         create_dns_record=string, create_dev_dns=string, create_ssl_cert=string, subdomain_name=string
#     }))
# }
# variable "cidr_block" {}
# variable "app_ips" { default = [] }
# variable "station_ips" { default = [] }
# variable "do_ssh_fingerprint" {}
# variable "do_region" {}
# variable "aws_region" {}
# variable "aws_access_key" {}
# variable "aws_secret_key" {}
# variable "do_token" {}
# variable "packer_config" {}
variable "config" {}
variable "stun_protos" { default = ["tcp", "udp"] }

provider "digitalocean" {
    token = var.config.do_token
}

locals {
    ## Loop through servers and change name if it does not contain admin
    ## TODO: Better handling how the role based name is added to machine name

    all_server_ids = tolist([
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.id
        if length(join(",", SERVER.tags)) > 0
    ])

    server_names = [
        for app in var.config.servers:
        element(app.roles, 0)
    ]

    lead_server_ips = tolist([
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.ipv4_address
        if length(regexall("lead", join(",", SERVER.tags))) > 0
    ])
    db_server_ips = tolist([
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.ipv4_address
        if length(regexall("db", join(",", SERVER.tags))) > 0
    ])
    admin_server_ips = tolist([
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.ipv4_address
        if length(regexall("admin", join(",", SERVER.tags))) > 0
    ])
    build_server_ips = tolist([
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.ipv4_address
        if length(regexall("build", join(",", SERVER.tags))) > 0
    ])



    admin_server_ids = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.id
        if length(regexall("admin", join(",", SERVER.tags))) > 0
    ]

    lead_server_ids = tolist([
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.id
        if length(regexall("lead", join(",", SERVER.tags))) > 0
    ])

    db_server_ids = tolist([
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.id
        if length(regexall("db", join(",", SERVER.tags))) > 0
    ])

    build_server_ids = tolist([
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.id
        if length(regexall("build", join(",", SERVER.tags))) > 0
    ])

    lead_servers = sum(concat([0], tolist([
        for SERVER in var.config.servers:
        SERVER.count
        if contains(SERVER.roles, "lead")
    ])))
    admin_servers = sum(concat([0], tolist([
        for SERVER in var.config.servers:
        SERVER.count
        if contains(SERVER.roles, "admin")
    ])))
    db_servers = sum(concat([0], tolist([
        for SERVER in var.config.servers:
        SERVER.count
        if contains(SERVER.roles, "db")
    ])))
    build_servers = sum(concat([0], tolist([
        for SERVER in var.config.servers:
        SERVER.count
        if contains(SERVER.roles, "build")
    ])))
}

# Based on app, create .db, .dev, and .dev.db subdomains (not used just yet)
# TODO: See if we can do locals like this in an envs/vars.tf file with a just declared variable
locals {
    cname_aliases = [
        for app in var.config.app_definitions:
        [app.subdomain_name, format("${app.subdomain_name}.db")]
        if app.create_dns_record == "true"
    ]
    cname_dev_aliases = [
        for app in var.config.app_definitions:
        [format("${app.subdomain_name}.dev"), format("${app.subdomain_name}.dev.db")]
        if app.create_dev_dns == "true"
    ]
    cname_additional_aliases = flatten([
        for domainname, domain in var.config.additional_domains : [
            for subdomainname, redirect in domain: {
                domainname = domainname
                subdomainname = subdomainname
            }
            if subdomainname != "@"
        ]
    ])

    consul = "CN-${var.config.packer_config.consul_version}"
    docker = "DK-${var.config.packer_config.docker_version}"
    dockerc = "DKC-${var.config.packer_config.docker_compose_version}"
    gitlab = "GL-${var.config.packer_config.gitlab_version}"
    redis = "R-${var.config.packer_config.redis_version}"
    do_image_name = "${local.consul}_${local.docker}_${local.dockerc}_${local.gitlab}_${local.redis}"
}
