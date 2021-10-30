## See wiki on creating placeholder_zone and delegation_set to get and set the delegationset id
## https://gitlab.codeopensrc.com/os/workbench/-/wikis/cloud-provider#aws
data "aws_route53_delegation_set" "dset" {
    id = var.config.placeholder_reusable_delegationset_id
}

resource "aws_route53_zone" "default" {
    name         = var.config.root_domain_name
    delegation_set_id = var.config.placeholder_reusable_delegationset_id
}

resource "aws_route53_zone" "additional" {
    for_each = var.config.additional_domains
    name = each.key
    delegation_set_id = var.config.placeholder_reusable_delegationset_id
}


resource "aws_route53_record" "additional_a_leader_root" {
    for_each = local.lead_servers > 0 ? var.config.additional_domains : {}
    zone_id         = aws_route53_zone.additional[each.key].zone_id
    name            = each.key
    allow_overwrite = true
    ttl             = "300"
    type            = "A"
    records  = [ data.aws_instances.lead.public_ips[0] ]
}

resource "aws_route53_record" "additional_cname" {
    for_each = {
        for ind, domain in local.cname_additional_aliases :
        "${domain.domainname}.${domain.subdomainname}" => domain
    }
    name            = each.value.subdomainname
    zone_id         = aws_route53_zone.additional[each.value.domainname].zone_id
    allow_overwrite = true
    type            = "CNAME"
    ttl             = "300"
    records = [ each.value.domainname ]
}

resource "aws_route53_record" "default_stun_srv_udp" {
    count           = var.config.stun_port != "" ? 1 : 0
    name            = "_stun_udp.${var.config.root_domain_name}"
    zone_id         = aws_route53_zone.default.zone_id
    allow_overwrite = true
    type            = "SRV"
    ttl             = "300"
    # Format:
    #     [priority] [weight] [port] [server host name]
    records = [ "0 0 ${var.config.stun_port} stun.${var.config.root_domain_name}" ]
}
resource "aws_route53_record" "default_stun_srv_tcp" {
    count           = var.config.stun_port != "" ? 1 : 0
    name            = "_stun_tcp.${var.config.root_domain_name}"
    zone_id         = aws_route53_zone.default.zone_id
    allow_overwrite = true
    type            = "SRV"
    ttl             = "300"
    # Format:
    #     [priority] [weight] [port] [server host name]
    records = [ "0 0 ${var.config.stun_port} stun.${var.config.root_domain_name}" ]
}

resource "aws_route53_record" "default_a_offsite" {
    count           = length(var.config.offsite_arecord_aliases)
    name            = var.config.offsite_arecord_aliases[count.index].name
    zone_id         = aws_route53_zone.default.zone_id
    allow_overwrite = true
    type            = "A"
    ttl             = "300"
    records         = [ var.config.offsite_arecord_aliases[count.index].ip ]
}

resource "aws_route53_record" "default_stun_a" {
    count           = var.config.stun_port != "" ? 1 : 0
    name            = "stun.${var.config.root_domain_name}"
    zone_id         = aws_route53_zone.default.zone_id
    allow_overwrite = true
    type            = "A"
    ttl             = "300"
    records  = [ data.aws_instances.lead.public_ips[0] ]
}

resource "aws_route53_record" "default_cname" {
    count           = length(compact(flatten(local.cname_aliases)))
    name            = compact(flatten(local.cname_aliases))[count.index]
    zone_id         = aws_route53_zone.default.zone_id
    allow_overwrite = true
    type            = "CNAME"
    ttl             = "300"
    records = [ var.config.root_domain_name ]
}

resource "aws_route53_record" "default_cname_dev" {
    count           = length(compact(flatten(local.cname_dev_aliases)))
    name            = compact(flatten(local.cname_dev_aliases))[count.index]
    zone_id         = aws_route53_zone.default.zone_id
    allow_overwrite = true
    type            = "CNAME"
    ttl             = "300"
    records = [ var.config.root_domain_name ]
}

resource "aws_route53_record" "default_a_admin" {
    count           = length(compact(var.config.admin_arecord_aliases))
    zone_id         = aws_route53_zone.default.zone_id
    name            = compact(var.config.admin_arecord_aliases)[count.index]
    allow_overwrite = true
    ttl             = "300"
    type            = "A"
    records  = [ local.admin_servers > 0 ? data.aws_instances.admin.public_ips[0]: data.aws_instances.lead.public_ips[0] ]
    # TODO: Check how we support tags changing while deployed as we have each aws_instance
    #  lifecycle attr set to     ignore_changes= [ tags ]
}

resource "aws_route53_record" "default_a_db" {
    count           = local.db_servers > 0 ? length(compact(var.config.db_arecord_aliases)) : 0
    zone_id         = aws_route53_zone.default.zone_id
    name            = compact(var.config.db_arecord_aliases)[count.index]
    allow_overwrite = true
    ttl             = "300"
    type            = "A"
    records  = [ data.aws_instances.db.public_ips[0] ]
}

resource "aws_route53_record" "default_a_leader" {
    count           = local.lead_servers > 0 ? length(compact(var.config.leader_arecord_aliases)) : 0
    zone_id         = aws_route53_zone.default.zone_id
    name            = compact(var.config.leader_arecord_aliases)[count.index]
    allow_overwrite = true
    ttl             = "300"
    type            = "A"
    # If ip matches an admin, go with admin ip or lead ip.
    # Atm choosing first lead ip due to docker proxy service listening port dependent on where it was originally launched
    # Make sure this only points to leader ip after it's joined the swarm, if we cant guarantee, dont change
    records  = [ data.aws_instances.lead.public_ips[0] ]

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
    count           = local.lead_servers > 0 ? 1 : 0
    zone_id         = aws_route53_zone.default.zone_id
    name            = var.config.root_domain_name
    allow_overwrite = true
    ttl             = "300"
    type            = "A"
    records  = [ data.aws_instances.lead.public_ips[0] ]
}

resource "aws_route53_record" "additional_ssl" {
    count  = local.lead_servers > 0 ? length(var.config.additional_ssl) : 0
    zone_id = aws_route53_zone.default.zone_id
    name   = lookup( element(var.config.additional_ssl, count.index), "subdomain_name")
    allow_overwrite = true
    type   = "CNAME"
    ttl    = "300"
    records = [ var.config.root_domain_name ]
}

resource "aws_route53_record" "misc_cname" {
    for_each = {
        for ind, domain in local.cname_misc_aliases :
        "${domain.subdomainname}" => domain
    }
    name            = each.value.subdomainname
    zone_id         = aws_route53_zone.default.zone_id
    allow_overwrite = true
    type            = "CNAME"
    ttl             = "300"
    records = [ each.value.alias ]
}
