resource "azurerm_dns_zone" "default" {
    name         = var.config.root_domain_name
    resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_dns_zone" "additional" {
    for_each            = var.config.additional_domains
    name                = each.key
    resource_group_name = azurerm_resource_group.main.name
}


resource "azurerm_dns_a_record" "additional_a_leader_root" {
    for_each = contains(flatten(local.cfg_servers[*].roles), "lead") ? var.config.additional_domains : {}
    zone_name           = azurerm_dns_zone.additional[each.key].name
    name                = each.key
    resource_group_name = azurerm_resource_group.main.name
    ttl                 = 300
    records             = [ local.dns_lead ]
    #target_resource_id   = element([
    #    for key, pip in azurerm_public_ip.main: pip.id
    #    if pip.ip == local.dns_lead
    #], 0)
}

resource "azurerm_dns_cname_record" "additional_cname" {
    for_each = {
        for ind, domain in local.cname_additional_aliases :
        "${domain.domainname}.${domain.subdomainname}" => domain
    }
    name                = each.value.subdomainname
    zone_name           = azurerm_dns_zone.additional[each.value.domainname].name
    resource_group_name = azurerm_resource_group.main.name
    ttl                 = 300
    record              = each.value.domainname
}

resource "azurerm_dns_srv_record" "default_stun_srv_udp" {
    count           = var.config.stun_port != "" ? 1 : 0
    name                = "_stun_udp.${var.config.root_domain_name}"
    zone_name           = azurerm_dns_zone.default.name
    resource_group_name = azurerm_resource_group.main.name
    ttl                 = 300

    record {
        priority = 0
        weight   = 0
        port     = var.config.stun_port
        target   = "stun.${var.config.root_domain_name}"
    }
}

resource "azurerm_dns_srv_record" "default_stun_srv_tcp" {
    count           = var.config.stun_port != "" ? 1 : 0
    name                = "_stun_tcp.${var.config.root_domain_name}"
    zone_name           = azurerm_dns_zone.default.name
    resource_group_name = azurerm_resource_group.main.name
    ttl                 = 300

    record {
        priority = 0
        weight   = 0
        port     = var.config.stun_port
        target   = "stun.${var.config.root_domain_name}"
    }
}

resource "azurerm_dns_a_record" "default_a_offsite" {
    count           = length(var.config.offsite_arecord_aliases)
    name            = var.config.offsite_arecord_aliases[count.index].name
    zone_name           = azurerm_dns_zone.default.name
    resource_group_name = azurerm_resource_group.main.name
    ttl                 = 300
    records             = [ var.config.offsite_arecord_aliases[count.index].ip ]
}

resource "azurerm_dns_a_record" "default_stun_a" {
    count           = var.config.stun_port != "" ? 1 : 0
    name            = "stun.${var.config.root_domain_name}"
    zone_name           = azurerm_dns_zone.default.name
    resource_group_name = azurerm_resource_group.main.name
    ttl                 = 300
    records             = [ local.dns_lead ]
    #target_resource_id   = element([
    #    for key, pip in azurerm_public_ip.main: pip.id
    #    if pip.ip_address == local.dns_lead
    #], 0)
}

resource "azurerm_dns_cname_record" "default_cname" {
    count           = length(compact(flatten(local.cname_aliases)))
    name            = compact(flatten(local.cname_aliases))[count.index]
    zone_name           = azurerm_dns_zone.default.name
    resource_group_name = azurerm_resource_group.main.name
    ttl                 = 300
    record              = var.config.root_domain_name
}

resource "azurerm_dns_cname_record" "default_cname_dev" {
    count           = length(compact(flatten(local.cname_dev_aliases)))
    name            = compact(flatten(local.cname_dev_aliases))[count.index]
    zone_name           = azurerm_dns_zone.default.name
    resource_group_name = azurerm_resource_group.main.name
    ttl                 = 300
    record              = var.config.root_domain_name
}

resource "azurerm_dns_a_record" "default_a_admin" {
    count           = length(compact(var.config.admin_arecord_aliases))
    name            = compact(var.config.admin_arecord_aliases)[count.index]
    zone_name           = azurerm_dns_zone.default.name
    resource_group_name = azurerm_resource_group.main.name
    ttl                 = 300
    records  = [ local.has_admin ? local.dns_admin : local.dns_lead ]
    #target_resource_id   = element([
    #    for key, pip in azurerm_public_ip.main: pip.id
    #    if pip.ip_address == (local.has_admin ? local.dns_admin : local.dns_lead)
    #], 0)
}

resource "azurerm_dns_a_record" "default_a_db" {
    count           = contains(flatten(local.cfg_servers[*].roles), "db") ? length(compact(var.config.db_arecord_aliases)) : 0
    name            = compact(var.config.db_arecord_aliases)[count.index]
    zone_name           = azurerm_dns_zone.default.name
    resource_group_name = azurerm_resource_group.main.name
    ttl                 = 300
    records  = [ local.dns_db ]
    #target_resource_id   = element([
    #    for key, pip in azurerm_public_ip.main: pip.id
    #    if pip.ip_address == local.dns_db
    #], 0)
}

resource "azurerm_dns_a_record" "default_a_leader" {
    count           = contains(flatten(local.cfg_servers[*].roles), "lead") ? length(compact(var.config.leader_arecord_aliases)) : 0
    name            = compact(var.config.leader_arecord_aliases)[count.index]
    zone_name           = azurerm_dns_zone.default.name
    resource_group_name = azurerm_resource_group.main.name
    ttl                 = 300
    records  = [ local.dns_lead ]
    #target_resource_id   = element([
    #    for key, pip in azurerm_public_ip.main: pip.id
    #    if pip.ip_address == local.dns_lead
    #], 0)
}

resource "azurerm_dns_a_record" "default_a_k8s_leader" {
    count  = local.create_kube_records && contains(flatten(local.cfg_servers[*].roles), "lead") ? 1 : 0
    name            = "*.k8s"
    zone_name           = azurerm_dns_zone.default.name
    resource_group_name = azurerm_resource_group.main.name
    ttl                 = 300
    records  = [ local.dns_lead ]
    #target_resource_id   = element([
    #    for key, pip in azurerm_public_ip.main: pip.id
    #    if pip.ip_address == local.dns_lead
    #], 0)
}

resource "azurerm_dns_a_record" "default_a_k8s_internal_leader" {
    count  = local.create_kube_records && contains(flatten(local.cfg_servers[*].roles), "lead") ? 1 : 0
    name            = "*.k8s-internal"
    zone_name           = azurerm_dns_zone.default.name
    resource_group_name = azurerm_resource_group.main.name
    ttl                 = 300
    ##TODO:  Not sure how internal will work on managed_kubernetes yet
    ## Feel like an additional internal nginx deployment is how itll work
    ## This is currently used for machines to resolve to pod IPs using their k8s ingress resource
    records  = [ "127.0.0.1" ]
    #target_resource_id   = element([
    #    for key, pip in azurerm_public_ip.main: pip.id
    #    if pip.ip_address == local.dns_lead
    #], 0)
}

resource "azurerm_dns_a_record" "default_a_leader_root" {
    count           = contains(flatten(local.cfg_servers[*].roles), "lead") ? 1 : 0
    name            = "@"
    zone_name           = azurerm_dns_zone.default.name
    resource_group_name = azurerm_resource_group.main.name
    ttl                 = 300
    records  = [ local.dns_lead ]
    #target_resource_id   = element([
    #    for key, pip in azurerm_public_ip.main: pip.id
    #    if pip.ip_address == local.dns_lead
    #], 0)
}

resource "azurerm_dns_cname_record" "additional_ssl" {
    count  = contains(flatten(local.cfg_servers[*].roles), "lead") ? length(var.config.additional_ssl) : 0
    name   = lookup( element(var.config.additional_ssl, count.index), "subdomain_name")
    zone_name           = azurerm_dns_zone.default.name
    resource_group_name = azurerm_resource_group.main.name
    ttl                 = 300
    record              = var.config.root_domain_name
}

resource "azurerm_dns_cname_record" "misc_cname" {
    for_each = {
        for ind, domain in local.cname_misc_aliases :
        "${domain.subdomainname}" => domain
    }
    name            = each.value.subdomainname
    zone_name           = azurerm_dns_zone.default.name
    resource_group_name = azurerm_resource_group.main.name
    ttl                 = 300
    record              = each.value.alias
}
