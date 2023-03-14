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
    cfg_servers = flatten([
        for ind, SERVER in var.config.servers: [
            for num in range(0, SERVER.count): {
                key = "${SERVER.fleet}-n${num}"
                server = SERVER
                role = SERVER.roles[0]
                roles = SERVER.roles
                size_priority = local.size_priority[SERVER.size]
                image_alias = local.image_alias[SERVER.roles[0]]
            }
        ]
    ])
}

## sorted machines by creation time then size
locals {
    has_admin = contains(flatten(local.cfg_servers[*].roles), "admin")

    all_ansible_hosts = tolist([
        for CFG in local.cfg_servers: {
            key = CFG.key
            machine_id = digitalocean_droplet.main[CFG.key].id
            name = digitalocean_droplet.main[CFG.key].name
            roles = CFG.roles
            role = CFG.role
            ip = digitalocean_droplet.main[CFG.key].ipv4_address
            private_ip = digitalocean_droplet.main[CFG.key].ipv4_address_private
            creation_time = time_static.creation_time[CFG.key].id
            size_priority = CFG.size_priority
        }
    ])

    ## Creates { role1=[{host}...], role2=[{host}...] }
    role_grouped_hosts = {
        for ind, host in local.all_ansible_hosts: (host.role) => host...
    }
    ## Creates { role1={timestamp=[{host}...], timestamp2=[{host}...]}, role2={timestamp=[{host}...]} }
    time_grouped_hosts = {
        for role, hosts in local.role_grouped_hosts:
        (role) => { for host in hosts: (host.creation_time) => host... }
    }
    ## Creates { role1={timestamp={size=[{host}...], size2=[{host}...]}, timestamp2={size=[{host}...]}}, role2={timestamp={size=[{host}...]}} }
    size_grouped_hosts = {
        for role, times in local.time_grouped_hosts:
        (role) => { for time, hosts in times:
            (time) => { for host in hosts: (host.size_priority) => host... }
        }
    }
    ## Creates { role1=[all_distinct_creation_times...], role2=[all_distinct_creation_times...] }
    sorted_times = {
        for role, hosts in local.role_grouped_hosts:
        (role) => sort(distinct([ for host in hosts: host.creation_time ]))
    }
    ## Creates { role1=[all_distinct_sizes...], role2=[all_distinct_sizes...] }
    sorted_sizes = {
        for role, hosts in local.role_grouped_hosts:
        (role) => reverse(sort(distinct([ for host in hosts: host.size_priority ])))
    }

    ## Groups hosts back into {role1=[{host}...], role2=[{host}...]}
    ## Hosts grouped by role are sorted by creation_time first -> size
    ## Intent is to have DNS point to the oldest/largest server
    sorted_hosts = {
        for role, times in local.sorted_times: (role) => flatten([
            for time in times: [
                for size in local.sorted_sizes[role]:
                local.size_grouped_hosts[role][time][size]
                if lookup(local.size_grouped_hosts[role][time], size, "") != ""
            ]
        ])
    }

    ## To prevent noise in dns when adding/updating unrelated servers, we first check
    ##  keys/role in remote_state_hosts. If none are available THEN check if any hosts
    ##  contain the role. It covers 95%+ of scenarios
    ## Reason being, sorting/aggregating based on resource data created at apply (time_static) causes anything
    ##  depending on that resource to not be known until apply. So if we aggregate build servers with web servers,
    ##  any change to build servers forces re-reads on web servers data. It does not know until apply if
    ##  the change ACTUALLY affects the web server order/data, forcing the re-read/update on apply.
    ## This is probably here to stay until something like giant public vs private clusters with no server roles
    ##  and launching containers/pods on either public/private cluster and all servers the same
    
    ## When scaling up, use old remote hosts, when scaling down/no change, use current hosts
    ## We dont want dns pointing to new servers as soon as theyre booted up, so point to remote_state_hosts
    ## We dont want dns pointing to servers set for decommissioning, (ones to destroy wont be in sorted_hosts)
    ##   so point to the current sorted_hosts

    num_remote_hosts = length(flatten(values(var.config.remote_state_hosts)))
    dnshosts = (local.num_remote_hosts > 0 && length(flatten(values(local.sorted_hosts))) > local.num_remote_hosts
        ? var.config.remote_state_hosts : local.sorted_hosts)

    # Check for main role first, if no main role, check if role attached to another host
    # Any use cases beyond what all this dns logic is doing, get static load balancer IP(s) and point to those
    dns_admin = (lookup(local.dnshosts, "admin", null) != null ? local.dnshosts["admin"][0].ip
        : (length(local.sorted_admin) > 0 ? local.sorted_admin[0].ip : ""))

    dns_lead = (lookup(local.dnshosts, "lead", null) != null ? local.dnshosts["lead"][0].ip
        : (length(local.sorted_lead) > 0 ? local.sorted_lead[0].ip : ""))

    dns_db = (lookup(local.dnshosts, "db", null) != null ? local.dnshosts["db"][0].ip
        : (length(local.sorted_db) > 0 ? local.sorted_db[0].ip : ""))


    ## Specific sorted lists per role for dns
    sorted_admin = flatten([
        for role, hosts in local.dnshosts: [
            for HOST in hosts: HOST
            if contains(HOST.roles, "admin")
        ]
    ])
    sorted_lead = flatten([
        for role, hosts in local.dnshosts: [
            for HOST in hosts: HOST
            if contains(HOST.roles, "lead")
        ]
    ])
    sorted_db = flatten([
        for role, hosts in local.dnshosts: [
            for HOST in hosts: HOST
            if contains(HOST.roles, "db")
        ]
    ])
}

## dns
locals {
    create_kube_records = var.config.create_kube_records
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
    gitlab = "GL-${var.config.packer_config.gitlab_version}"
    redis = "R-${var.config.packer_config.redis_version}"
    kubernetes = "K-${var.config.packer_config.kubernetes_version}"
    image_str = join("_", [
        local.consul,
        local.docker,
        local.gitlab,
        local.redis,
        local.kubernetes
    ])
    small_image_name = uuidv5("dns", replace(local.image_str, "${local.gitlab}_", ""))
    large_image_name = uuidv5("dns", local.image_str)

    do_tags = [
        "${replace(local.consul, ".", "-")}",
        "${replace(local.docker, ".", "-")}",
        "${replace(local.gitlab, ".", "-")}",
        "${replace(local.redis, ".", "-")}",
        "${replace(local.kubernetes, ".", "-")}"
    ]
    do_small_tags = [
        "${replace(local.consul, ".", "-")}",
        "${replace(local.docker, ".", "-")}",
        "${replace(local.redis, ".", "-")}",
        "${replace(local.kubernetes, ".", "-")}"
    ]

    tags = {
        "admin" = local.do_tags
        "lead" = local.do_small_tags
        "db" = local.do_small_tags
        "build" = local.do_small_tags
    }
    image_alias = {
        "admin" = "large"
        "lead" = "small"
        "db" = "small"
        "build" = "small"
    }
    ##NOTE: image_size is packer snapshot size, not instance size
    packer_images = {
        "large" = {
            "name" = local.large_image_name,
            "size" = "s-2vcpu-4gb"
        }
        "small" = {
            "name" = local.small_image_name,
            "size" = "s-1vcpu-1gb"
        }
    }
}

## kubernetes/managed_kubernetes
locals {
    use_lb = contains(var.config.container_orchestrators, "managed_kubernetes")
    use_kube_managed_lb = length(local.cfg_servers) == 1 && local.create_kube_records
    lb_name = "${var.config.do_lb_name}"
    lb_http_nodeport = var.config.kubernetes_nginx_nodeports.http ## Must be valid kubernetes nodeport: 30000-32767
    lb_https_nodeport = var.config.kubernetes_nginx_nodeports.https ## Must be valid kubernetes nodeport: 30000-32767
    lb_starting_udp_nodeport = 31100
    lb_starting_tcp_nodeport = 31200
    lb_udp_nodeports = {
        for ind, port in keys(lookup(var.config.kubernetes_nginx_nodeports, "udp", {})):
        "${port}" => sum([local.lb_starting_udp_nodeport, ind])
    }
    lb_tcp_nodeports = {
        for ind, port in keys(lookup(var.config.kubernetes_nginx_nodeports, "tcp", {})):
        "${port}" => sum([local.lb_starting_tcp_nodeport, ind])
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
