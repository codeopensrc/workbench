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
    for_each = contains(flatten(local.cfg_servers[*].roles), "lead") ? var.config.additional_domains : {}
    zone_id         = aws_route53_zone.additional[each.key].zone_id
    name            = each.key
    allow_overwrite = true
    ttl             = "300"
    type            = "A"
    records  = [ local.dns_lead ]
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
    records  = [ local.dns_lead ]
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
    records  = [ local.has_admin ? local.dns_admin : local.dns_lead ]
}

resource "aws_route53_record" "default_a_db" {
    count           = contains(flatten(local.cfg_servers[*].roles), "db") ? length(compact(var.config.db_arecord_aliases)) : 0
    zone_id         = aws_route53_zone.default.zone_id
    name            = compact(var.config.db_arecord_aliases)[count.index]
    allow_overwrite = true
    ttl             = "300"
    type            = "A"
    records  = [ local.dns_db ]
}

resource "aws_route53_record" "default_a_leader" {
    count           = contains(flatten(local.cfg_servers[*].roles), "lead") ? length(compact(var.config.leader_arecord_aliases)) : 0
    zone_id         = aws_route53_zone.default.zone_id
    name            = compact(var.config.leader_arecord_aliases)[count.index]
    allow_overwrite = true
    ttl             = "300"
    type            = "A"
    records  = [ local.dns_lead ]
}

resource "aws_route53_record" "default_a_k8s_leader" {
    count  = local.create_kube_records && contains(flatten(local.cfg_servers[*].roles), "lead") ? 1 : 0
    zone_id         = aws_route53_zone.default.zone_id
    name            = "*.k8s"
    allow_overwrite = true
    ttl             = "300"
    type            = "A"
    records = [ local.dns_lead ]
}

resource "aws_route53_record" "default_a_k8s_internal_leader" {
    count  = local.create_kube_records && contains(flatten(local.cfg_servers[*].roles), "lead") ? 1 : 0
    zone_id         = aws_route53_zone.default.zone_id
    name            = "*.k8s-internal"
    allow_overwrite = true
    ttl             = "300"
    type            = "A"
    ##TODO:  Not sure how internal will work on managed_kubernetes yet
    ## Feel like an additional internal nginx deployment is how itll work
    ## This is currently used for machines to resolve to pod IPs using their k8s ingress resource
    records  = [ "127.0.0.1" ]
}

resource "aws_route53_record" "default_a_leader_root" {
    count           = contains(flatten(local.cfg_servers[*].roles), "lead") ? 1 : 0
    zone_id         = aws_route53_zone.default.zone_id
    name            = var.config.root_domain_name
    allow_overwrite = true
    ttl             = "300"
    type            = "A"
    records  = [ local.dns_lead ]
}

resource "aws_route53_record" "additional_ssl" {
    count  = contains(flatten(local.cfg_servers[*].roles), "lead") ? length(var.config.additional_ssl) : 0
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
