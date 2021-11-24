### See envs/env/main.tf locals.config
variable "config" {}

variable "stun_protos" { default = ["tcp", "udp"] }

## input/config
locals {
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
    admin_public_ips = flatten([
        for host in local.sorted_hosts: host.ip
        if contains(host.roles, "admin")
    ])
    lead_public_ips = flatten([
        for host in local.sorted_hosts: host.ip
        if contains(host.roles, "lead")
    ])
    db_public_ips = flatten([
        for host in local.sorted_hosts: host.ip
        if contains(host.roles, "db")
    ])
    build_public_ips = flatten([
        for host in local.sorted_hosts: host.ip
        if contains(host.roles, "build")
    ])

    admin_server_ids = flatten([
        for host in local.sorted_hosts: host.machine_id
        if contains(host.roles, "admin")
    ])
    lead_server_ids = flatten([
        for host in local.sorted_hosts: host.machine_id
        if contains(host.roles, "lead")
    ])
    db_server_ids = flatten([
        for host in local.sorted_hosts: host.machine_id
        if contains(host.roles, "db")
    ])
    build_server_ids = flatten([
        for host in local.sorted_hosts: host.machine_id
        if contains(host.roles, "build")
    ])
    all_server_ids = distinct(concat(local.admin_server_ids, local.lead_server_ids, local.db_server_ids, local.build_server_ids))

    admin_server_instances = [for v in module.admin : v.instance]
    lead_server_instances = [for v in module.lead : v.instance]
    db_server_instances = [for v in module.db : v.instance]
    build_server_instances = [for v in module.build : v.instance]
    all_server_instances = concat(local.admin_server_instances, local.lead_server_instances, local.db_server_instances, local.build_server_instances)

    admin_ansible_hosts = [for v in module.admin : v.ansible_host]
    lead_ansible_hosts = [for v in module.lead : v.ansible_host]
    db_ansible_hosts = [for v in module.db : v.ansible_host]
    build_ansible_hosts = [for v in module.build : v.ansible_host]
    all_ansible_hosts = concat(local.admin_ansible_hosts, local.lead_ansible_hosts, local.db_ansible_hosts, local.build_ansible_hosts)
}

##TODO: Test sorting by descending creation_time so scaling up adds machines
##  but scaling down removes the oldest node - builds or leads servers that are not kube admins
## Dont think its fully achievable until almost ALL provisioning done via ansible due to terraform
##   needing the exact resource count and any random names/uuids known before apply, otherwise we're
##   just doing more complicated indexed based provisioning

## sorted machines by creation time then size
locals {
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

## vpc for aws_instance
locals {
    vpc = {
        aws_subnet = { public_subnet = aws_subnet.public_subnet }
        aws_route_table_association = { public_subnet_assoc = aws_route_table_association.public_subnet_assoc }
        aws_route_table = { rtb = aws_route_table.rtb }
        aws_route = { internet_access = aws_route.internet_access }
        aws_internet_gateway = { igw = aws_internet_gateway.igw }
        aws_security_group = {
            default_ports = aws_security_group.default_ports
            ext_remote = aws_security_group.ext_remote
            admin_ports = aws_security_group.admin_ports
            app_ports = aws_security_group.app_ports
            db_ports = aws_security_group.db_ports
            ext_db = aws_security_group.ext_db
        }
    }
}

provider "aws" {
    region = var.config.aws_region

    # profile = "${var.profile}"
    access_key = var.config.aws_access_key
    secret_key = var.config.aws_secret_key
}
