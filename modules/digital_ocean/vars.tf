### See envs/env/main.tf locals.config
variable "config" {}

variable "stun_protos" { default = ["tcp", "udp"] }

## input/config
locals {
    ##TODO: Dynamic or list all sizes
    size_priority = {
        "s-1vcpu-1gb" = "1",
        "s-1vcpu-2gb" = "2",
        "s-2vcpu-2gb" = "3",
        "s-2vcpu-4gb" = "4",
        "s-4vcpu-8gb" = "5",
    }
    ##TODO: Attempt to support "pet_names" or uuids instead of -nIND after fully converted to ansible provisioning
    ## https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/pet
    cfg_servers = flatten([
        for ind, SERVER in var.config.servers: [
            for num in range(0, SERVER.count): {
                key = "${SERVER.fleet}-n${num}"
                server = SERVER
                role = SERVER.roles[0]
                roles = SERVER.roles
                size_priority = local.size_priority[SERVER.size["digital_ocean"]]
            }
        ]
    ])
}

##TODO: Test sorting by descending creation_time so scaling up adds machines
##  but scaling down removes the oldest node - builds or leads servers that are not kube admins
## Dont think its fully achievable until almost ALL provisioning done via ansible due to terraform
##   needing the exact resource count and any random names/uuids known before apply, otherwise we're
##   just doing more complicated indexed based provisioning

## sorted machines by creation time then size
locals {
    all_ansible_hosts = tolist([
        for CFG in local.cfg_servers: {
            machine_id = digitalocean_droplet.main[CFG.key].id
            name = digitalocean_droplet.main[CFG.key].name
            roles = CFG.roles
            ip = digitalocean_droplet.main[CFG.key].ipv4_address
            private_ip = digitalocean_droplet.main[CFG.key].ipv4_address_private
            creation_time = time_static.creation_time[CFG.key].id
            size_priority = CFG.size_priority
        }
    ])
    time_grouped_hosts = {
        for ind, host in local.all_ansible_hosts: (host.creation_time) => host...
    }
    time_then_size_grouped_hosts = {
        for time, hosts in local.time_grouped_hosts:
        (time) => { for host in hosts: (host.size_priority) => host... }
    }
    sorted_times = sort(distinct(local.all_ansible_hosts[*].creation_time))
    sorted_sizes = reverse(sort(distinct(local.all_ansible_hosts[*].size_priority)))
    sorted_hosts = flatten([
        for time in local.sorted_times: [
            for size in local.sorted_sizes:
            local.time_then_size_grouped_hosts[time][size]
            if lookup(local.time_then_size_grouped_hosts[time], size, "") != ""
        ]
    ])
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

    tags = {
        "admin" = local.do_tags
        "lead" = local.do_small_tags
        "db" = local.do_small_tags
        "build" = local.do_small_tags
    }
    ##NOTE: image_size is packer snapshot size, not instance size
    image_size = {
        "admin" = "s-2vcpu-4gb"
        "lead" = "s-1vcpu-1gb"
        "db" = "s-1vcpu-1gb"
        "build" = "s-1vcpu-1gb"
    }
    image_name = {
        "admin" = local.do_image_name
        "lead" = local.do_image_small_name
        "db" = local.do_image_small_name
        "build" = local.do_image_small_name
    }
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
