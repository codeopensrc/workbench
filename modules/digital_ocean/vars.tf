terraform {
    required_providers {
        digitalocean = {
            source = "digitalocean/digitalocean"
        }
    }
    required_version = ">=0.13"
}

### All in config{}
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
# variable "additional_ssl" { type = list }
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
# variable "misc_cname" {}
variable "config" {}
variable "stun_protos" { default = ["tcp", "udp"] }

provider "digitalocean" {
    token = var.config.do_token
}

locals {
    server_names = [
        for app in var.config.servers:
        element(app.roles, 0)
    ]
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
    ## The "l" and "d" using _extra, is to allow lead and db on the admin allowing
    ##  a single server to use admin + lead + db.
    ## TODO: Hmm lightbulb moment:
    ##   If no lead, use admin. If no db, use lead or admin
    ## Entire infra depends on at a minimum lead + db roles so if they are NOT there
    ##  then they MUST be attached to admin. Inverse is not true, we're attempting to
    ##  have admin NOT be mandatory
    admin_private_ips = flatten(module.admin[*].ipv4_addresses_private)
    admin_l_private_ips = flatten(module.admin[*].ipv4_addresses_private_extra_lead)
    admin_d_private_ips = flatten(module.admin[*].ipv4_addresses_private_extra_db)
    lead_private_ips = flatten(module.lead[*].ipv4_addresses_private)
    db_private_ips = flatten(module.db[*].ipv4_addresses_private)
    build_private_ips = flatten(module.build[*].ipv4_addresses_private)

    admin_public_ips = flatten(module.admin[*].ipv4_addresses)
    admin_l_public_ips = flatten(module.admin[*].ipv4_addresses_extra_lead)
    admin_d_public_ips = flatten(module.admin[*].ipv4_addresses_extra_db)
    lead_public_ips = flatten(module.lead[*].ipv4_addresses)
    db_public_ips = flatten(module.db[*].ipv4_addresses)
    build_public_ips = flatten(module.build[*].ipv4_addresses)

    admin_names = flatten(module.admin[*].names)
    admin_l_names = flatten(module.admin[*].names_extra_lead)
    admin_d_names = flatten(module.admin[*].names_extra_db)
    lead_names = flatten(module.lead[*].names)
    db_names = flatten(module.db[*].names)
    build_names = flatten(module.build[*].names)

    admin_server_ids = flatten(module.admin[*].ids)
    admin_l_server_ids = flatten(module.admin[*].ids_extra_lead)
    admin_d_server_ids = flatten(module.admin[*].ids_extra_db)
    lead_server_ids = flatten(module.lead[*].ids)
    db_server_ids = flatten(module.db[*].ids)
    build_server_ids = flatten(module.build[*].ids)

    admin_server_instances = flatten(module.admin[*].instances)
    lead_server_instances = flatten(module.lead[*].instances)
    db_server_instances = flatten(module.db[*].instances)
    build_server_instances = flatten(module.build[*].instances)

    all_lead_private_ips = concat(local.admin_l_private_ips, local.lead_private_ips)
    all_lead_public_ips = concat(local.admin_l_public_ips, local.lead_public_ips)
    all_lead_names = concat(local.admin_l_names, local.lead_names)
    all_lead_server_ids = concat(local.admin_l_server_ids, local.lead_server_ids)

    all_db_private_ips = concat(local.admin_d_private_ips, local.db_private_ips)
    all_db_public_ips = concat(local.admin_d_public_ips, local.db_public_ips)
    all_db_names = concat(local.admin_d_names, local.db_names)
    all_db_server_ids = concat(local.admin_d_server_ids, local.db_server_ids)

    all_public_ips = distinct(concat(local.admin_public_ips, local.all_lead_public_ips, local.all_db_public_ips, local.build_public_ips))
    all_names = distinct(concat(local.admin_names, local.all_lead_names, local.all_db_names, local.build_names))
    all_server_ids = distinct(concat(local.admin_server_ids, local.all_lead_server_ids, local.all_db_server_ids, local.build_server_ids))
    all_server_instances = concat(local.admin_server_instances, local.lead_server_instances, local.db_server_instances, local.build_server_instances)
}

# Based on app, create .db, .beta, and .beta.db subdomains (not used just yet)
# TODO: See if we can do locals like this in an envs/vars.tf file with a just declared variable
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
