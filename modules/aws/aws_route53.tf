data "aws_route53_zone" "default" {
    name         = var.root_domain_name
}

# Based on app, create .db, .dev, and .dev.db subdomains (not used just yet)
# TODO: See if we can do locals like this in an envs/vars.tf file with a just declared variable
locals {
    cname_aliases = [
        for app in var.app_definitions:
        [app.subdomain_name, format("${app.subdomain_name}.db")]
        if app.create_dns_record == "true"
    ]
    cname_dev_aliases = [
        for app in var.app_definitions:
        [format("${app.subdomain_name}.dev"), format("${app.subdomain_name}.dev.db")]
        if app.create_dev_dns == "true"
    ]
}

resource "aws_route53_record" "default_stun_srv_udp" {
    count           = var.active_env_provider == "aws" && var.dns_provider == "aws_route53" && var.stun_port != "" ? 1 : 0
    name            = "_stun_udp.${var.root_domain_name}"
    zone_id         = data.aws_route53_zone.default.zone_id
    allow_overwrite = true
    type            = "SRV"
    ttl             = "300"
    # Format:
    #     [priority] [weight] [port] [server host name]
    records = [ "0 0 ${var.stun_port} stun.${var.root_domain_name}" ]
}
resource "aws_route53_record" "default_stun_srv_tcp" {
    count           = var.active_env_provider == "aws" && var.dns_provider == "aws_route53" && var.stun_port != "" ? 1 : 0
    name            = "_stun_tcp.${var.root_domain_name}"
    zone_id         = data.aws_route53_zone.default.zone_id
    allow_overwrite = true
    type            = "SRV"
    ttl             = "300"
    # Format:
    #     [priority] [weight] [port] [server host name]
    records = [ "0 0 ${var.stun_port} stun.${var.root_domain_name}" ]
}

resource "aws_route53_record" "default_stun_a" {
    count           = var.active_env_provider == "aws" && var.dns_provider == "aws_route53" && var.stun_port != "" ? 1 : 0
    name            = "stun.${var.root_domain_name}"
    zone_id         = data.aws_route53_zone.default.zone_id
    allow_overwrite = true
    type            = "A"
    ttl             = "300"
    records = slice(local.lead_server_ips, 0, 1)
}

resource "aws_route53_record" "default_cname" {
    count           = var.active_env_provider == "aws" && var.dns_provider == "aws_route53" ? length(compact(flatten(local.cname_aliases))) : 0
    name            = compact(flatten(local.cname_aliases))[count.index]
    zone_id         = data.aws_route53_zone.default.zone_id
    allow_overwrite = true
    type            = "CNAME"
    ttl             = "300"
    records = [ var.root_domain_name ]
}

resource "aws_route53_record" "default_cname_dev" {
    count           = var.active_env_provider == "aws" && var.dns_provider == "aws_route53" ? length(compact(flatten(local.cname_dev_aliases))) : 0
    name            = compact(flatten(local.cname_dev_aliases))[count.index]
    zone_id         = data.aws_route53_zone.default.zone_id
    allow_overwrite = true
    type            = "CNAME"
    ttl             = "300"
    records = [ var.root_domain_name ]
}

resource "aws_route53_record" "default_a_admin" {
    count           = var.active_env_provider == "aws" && var.dns_provider == "aws_route53" ? length(compact(var.admin_arecord_aliases)) : 0
    zone_id         = data.aws_route53_zone.default.zone_id
    name            = compact(var.admin_arecord_aliases)[count.index]
    allow_overwrite = true
    ttl             = "300"
    type            = "A"
    # TODO: Check how we support tags changing while deployed as we have each aws_instance
    #  lifecycle attr set to     ignore_changes= [ tags ]
    records = [
        for SERVER in aws_instance.main[*]:
        SERVER.public_ip
        if length(regexall("admin", SERVER.tags.Roles)) > 0
    ]
}

resource "aws_route53_record" "default_a_db" {
    count           = var.active_env_provider == "aws" && var.dns_provider == "aws_route53" ? length(compact(var.db_arecord_aliases)) : 0
    zone_id         = data.aws_route53_zone.default.zone_id
    name            = compact(var.db_arecord_aliases)[count.index]
    allow_overwrite = true
    ttl             = "300"
    type            = "A"
    records = slice([
        for SERVER in aws_instance.main[*]:
        SERVER.public_ip
        if length(regexall("db", SERVER.tags.Roles)) > 0
    ], 0, 1)
}

resource "aws_route53_record" "default_a_leader" {
    count           = var.active_env_provider == "aws" && var.dns_provider == "aws_route53" ? length(compact(var.leader_arecord_aliases)) : 0
    zone_id         = data.aws_route53_zone.default.zone_id
    name            = compact(var.leader_arecord_aliases)[count.index]
    allow_overwrite = true
    ttl             = "300"
    type            = "A"
    # If ip matches an admin, go with admin ip or lead ip.
    # Atm choosing first lead ip due to docker proxy service listening port dependent on where it was originally launched
    # Make sure this only points to leader ip after it's joined the swarm, if we cant guarantee, dont change
    records = slice(local.lead_server_ips, 0, 1)

    # Get first ip
    # records = slice([
    #     for SERVER in aws_instance.main[*]:
    #     SERVER.public_ip
    #     if length(regexall("lead", SERVER.tags.Roles)) > 0
    # ], 0, 1)
    # If we wanted the last ip
    # records = slice(local.lead_server_ips,
    #     (length(local.lead_server_ips) - 1 > 0 ? length(local.lead_server_ips) - 1 : 0),  #start index
    #     (length(local.lead_server_ips) > 1 ? length(local.lead_server_ips) : 1)   #end index
    # )
}

resource "aws_route53_record" "default_a_leader_root" {
    count           = var.active_env_provider == "aws" && var.dns_provider == "aws_route53" ? 1 : 0
    zone_id         = data.aws_route53_zone.default.zone_id
    name            = var.root_domain_name
    allow_overwrite = true
    ttl             = "300"
    type            = "A"
    records = slice(local.lead_server_ips, 0, 1)
    # records = slice([
    #     for SERVER in aws_instance.main[*]:
    #     SERVER.public_ip
    #     if length(regexall("lead", SERVER.tags.Roles)) > 0
    # ], 0, 1)
}
