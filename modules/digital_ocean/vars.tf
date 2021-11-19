### See envs/env/main.tf locals.config
variable "config" {}

variable "stun_protos" { default = ["tcp", "udp"] }

## input/config
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

    admin_cfg_servers = flatten([
        for ind, SERVER in var.config.servers: [
            for num in range(0, SERVER.count): {
                key = "${SERVER.fleet}-n${num}"
                server = SERVER
            }
            if SERVER.roles[0] == "admin"
        ]
    ])
    lead_cfg_servers = flatten([
        for ind, SERVER in var.config.servers: [
            for num in range(0, SERVER.count): {
                key = "${SERVER.fleet}-n${num}"
                server = SERVER
            }
            if SERVER.roles[0] == "lead"
        ]
    ])
    db_cfg_servers = flatten([
        for ind, SERVER in var.config.servers: [
            for num in range(0, SERVER.count): {
                key = "${SERVER.fleet}-n${num}"
                server = SERVER
            }
            if SERVER.roles[0] == "db"
        ]
    ])
    build_cfg_servers = flatten([
        for ind, SERVER in var.config.servers: [
            for num in range(0, SERVER.count): {
                key = "${SERVER.fleet}-n${num}"
                server = SERVER
            }
            if SERVER.roles[0] == "build"
        ]
    ])
}

## output/aggregation
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

    admin_server_ids = [for v in module.admin : v.id]
    lead_server_ids = [for v in module.lead : v.id]
    db_server_ids = [for v in module.db : v.id]
    build_server_ids = [for v in module.build : v.id]

    admin_server_instances = [for v in module.admin : v.instance]
    lead_server_instances = [for v in module.lead : v.instance]
    db_server_instances = [for v in module.db : v.instance]
    build_server_instances = [for v in module.build : v.instance]

    admin_ansible_hosts = [for v in module.admin : v.ansible_host]
    lead_ansible_hosts = [for v in module.lead : v.ansible_host]
    db_ansible_hosts = [for v in module.db : v.ansible_host]
    build_ansible_hosts = [for v in module.build : v.ansible_host]

    all_server_ids = distinct(concat(local.admin_server_ids, local.lead_server_ids, local.db_server_ids, local.build_server_ids))
    all_server_instances = concat(local.admin_server_instances, local.lead_server_instances, local.db_server_instances, local.build_server_instances)
    all_ansible_hosts = concat(local.admin_ansible_hosts, local.lead_ansible_hosts, local.db_ansible_hosts, local.build_ansible_hosts)
}

## dns
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
}

## packer
locals {
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
