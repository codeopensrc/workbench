### See envs/env/main.tf locals.config
variable "config" {}

variable "stun_protos" { default = ["tcp", "udp"] }

locals {
    is_not_admin_count = sum([local.is_only_leader_count, local.is_only_db_count, local.is_only_build_count])
    ## Allows db with lead
    is_only_leader_count = sum(concat([0], tolist([
        for SERVER in var.config.servers:
        SERVER.count
        if contains(SERVER.roles, "lead") && !contains(SERVER.roles, "admin")
    ])))
    is_only_db_count = sum(concat([0], tolist([
        for SERVER in var.config.servers:
        SERVER.count
        if contains(SERVER.roles, "db") && length(SERVER.roles) == 1
    ])))
    is_only_build_count = sum(concat([0], tolist([
        for SERVER in var.config.servers:
        SERVER.count
        if contains(SERVER.roles, "build") && length(SERVER.roles) == 1
    ])))

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


    admin_cfg_servers = tolist([
        for SERVER in var.config.servers:
        SERVER
        if SERVER.roles[0] == "admin"
    ])
    lead_cfg_servers = tolist([
        for SERVER in var.config.servers:
        SERVER
        if SERVER.roles[0] == "lead"
    ])
    db_cfg_servers = tolist([
        for SERVER in var.config.servers:
        SERVER
        if SERVER.roles[0] == "db"
    ])
    build_cfg_servers = tolist([
        for SERVER in var.config.servers:
        SERVER
        if SERVER.roles[0] == "build"
    ])

}

locals {
    admin_private_ips = data.digitalocean_droplets.admin.droplets[*].ipv4_address_private
    lead_private_ips = data.digitalocean_droplets.lead.droplets[*].ipv4_address_private
    db_private_ips = data.digitalocean_droplets.db.droplets[*].ipv4_address_private
    build_private_ips = data.digitalocean_droplets.build.droplets[*].ipv4_address_private

    admin_public_ips = data.digitalocean_droplets.admin.droplets[*].ipv4_address
    lead_public_ips = data.digitalocean_droplets.lead.droplets[*].ipv4_address
    db_public_ips = data.digitalocean_droplets.db.droplets[*].ipv4_address
    build_public_ips = data.digitalocean_droplets.build.droplets[*].ipv4_address

    admin_names = data.digitalocean_droplets.admin.droplets[*].name
    lead_names = data.digitalocean_droplets.lead.droplets[*].name
    db_names = data.digitalocean_droplets.db.droplets[*].name
    build_names = data.digitalocean_droplets.build.droplets[*].name

    admin_server_ids = data.digitalocean_droplets.admin.droplets[*].id
    lead_server_ids = data.digitalocean_droplets.lead.droplets[*].id
    db_server_ids = data.digitalocean_droplets.db.droplets[*].id
    build_server_ids = data.digitalocean_droplets.build.droplets[*].id

    admin_server_instances = flatten(module.admin[*].instance)
    lead_server_instances = flatten(module.lead[*].instance)
    db_server_instances = flatten(module.db[*].instance)
    build_server_instances = flatten(module.build[*].instance)

    admin_ansible_hosts = flatten(module.admin[*].ansible_host)
    lead_ansible_hosts = flatten(module.lead[*].ansible_host)
    db_ansible_hosts = flatten(module.db[*].ansible_host)
    build_ansible_hosts = flatten(module.build[*].ansible_host)

    all_server_ids = distinct(concat(local.admin_server_ids, local.lead_server_ids, local.db_server_ids, local.build_server_ids))
    all_server_instances = concat(local.admin_server_instances, local.lead_server_instances, local.db_server_instances, local.build_server_instances)
    all_ansible_hosts = concat(local.admin_ansible_hosts, local.lead_ansible_hosts, local.db_ansible_hosts, local.build_ansible_hosts)
}

locals {
    cname_aliases = [
        for app in var.config.app_definitions:
        [app.subdomain_name, format("${app.subdomain_name}.db")]
        if app.create_dns_record == "true"
    ]
    cname_dev_aliases = [
        for app in var.config.app_definitions:
        [format("${app.subdomain_name}.beta"), format("${app.subdomain_name}.beta.db")]
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
    cname_misc_aliases = flatten(var.config.misc_cnames)

    consul = "CN-${var.config.packer_config.consul_version}"
    docker = "DK-${var.config.packer_config.docker_version}"
    dockerc = "DKC-${var.config.packer_config.docker_compose_version}"
    gitlab = "GL-${var.config.packer_config.gitlab_version}"
    redis = "R-${var.config.packer_config.redis_version}"
    do_image_name = uuidv5("dns", "${local.consul}_${local.docker}_${local.dockerc}_${local.gitlab}_${local.redis}")
    do_image_small_name = uuidv5("dns", "${local.consul}_${local.docker}_${local.dockerc}_${local.redis}")

    do_tags = [
        "${replace(local.consul, ".", "-")}",
        "${replace(local.docker, ".", "-")}",
        "${replace(local.dockerc, ".", "-")}",
        "${replace(local.gitlab, ".", "-")}",
        "${replace(local.redis, ".", "-")}"
    ]
    do_small_tags = [
        "${replace(local.consul, ".", "-")}",
        "${replace(local.docker, ".", "-")}",
        "${replace(local.dockerc, ".", "-")}",
        "${replace(local.redis, ".", "-")}"
    ]
}

terraform {
    required_providers {
        digitalocean = {
            source = "digitalocean/digitalocean"
        }
    }
    required_version = ">=0.13"
}

provider "digitalocean" {
    token = var.config.do_token
}
