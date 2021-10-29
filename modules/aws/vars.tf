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
    admin_private_ips = data.aws_instances.admin.private_ips[*]
    lead_private_ips = data.aws_instances.lead.private_ips[*]
    db_private_ips = data.aws_instances.db.private_ips[*]
    build_private_ips = data.aws_instances.build.private_ips[*]

    admin_public_ips = data.aws_instances.admin.public_ips[*]
    lead_public_ips = data.aws_instances.lead.public_ips[*]
    db_public_ips = data.aws_instances.db.public_ips[*]
    build_public_ips = data.aws_instances.build.public_ips[*]

    admin_server_ids = data.aws_instances.admin.ids[*]
    lead_server_ids = data.aws_instances.lead.ids[*]
    db_server_ids = data.aws_instances.db.ids[*]
    build_server_ids = data.aws_instances.build.ids[*]

    admin_names = flatten(module.admin[*].tags.Name)
    lead_names = flatten([
        for mod in flatten([module.admin[*], module.lead[*]]):
        mod.tags.Name  
        if mod.tags.Lead == "true"
    ])
    db_names = flatten([
        for mod in flatten([module.admin[*], module.db[*]]):
        mod.tags.Name  
        if mod.tags.DB == "true"
    ])
    build_names = flatten([
        for mod in flatten([module.admin[*], module.build[*]]):
        mod.tags.Name  
        if mod.tags.Build == "true"
    ])

    admin_server_instances = flatten(module.admin[*].instance)
    lead_server_instances = flatten(module.lead[*].instance)
    db_server_instances = flatten(module.db[*].instance)
    build_server_instances = flatten(module.build[*].instance)

    all_server_ids = distinct(concat(local.admin_server_ids, local.lead_server_ids, local.db_server_ids, local.build_server_ids))
    all_server_instances = concat(local.admin_server_instances, local.lead_server_instances, local.db_server_instances, local.build_server_instances)
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
