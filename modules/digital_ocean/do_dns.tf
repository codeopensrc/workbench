resource "digitalocean_domain" "additional" {
    for_each = var.config.additional_domains
    name = each.key
    ip_address  = local.dns_admin
}

resource "digitalocean_record" "additional_cname" {
    depends_on = [ digitalocean_domain.additional ]
    for_each = {
        for ind, domain in local.cname_additional_aliases :
        "${domain.domainname}.${domain.subdomainname}" => domain
    }
    name   = each.value.subdomainname
    domain = each.value.domainname
    type   = "CNAME"
    ttl    = "300"
    value  = "${each.value.domainname}."
}

resource "digitalocean_domain" "default" {
    name = var.config.root_domain_name
}


resource "digitalocean_record" "default_stun_srv_udp" {
    count = var.config.stun_port != "" ? 1 : 0
    name   = "_stun._udp"
    domain = digitalocean_domain.default.name
    type   = "SRV"
    ttl    = "300"
    priority = "0"
    weight = "0"
    port = var.config.stun_port
    value  = "stun.${var.config.root_domain_name}."
}

resource "digitalocean_record" "default_stun_srv_tcp" {
    count = var.config.stun_port != "" ? 1 : 0
    name   = "_stun._tcp"
    domain = digitalocean_domain.default.name
    type   = "SRV"
    ttl    = "300"
    priority = "0"
    weight = "0"
    port = var.config.stun_port
    value  = "stun.${var.config.root_domain_name}."
}

resource "digitalocean_record" "default_a_offsite" {
    count = length(var.config.offsite_arecord_aliases)
    name   = var.config.offsite_arecord_aliases[count.index].name
    domain = digitalocean_domain.default.name
    type   = "A"
    ttl    = "300"
    value  = var.config.offsite_arecord_aliases[count.index].ip
}

resource "digitalocean_record" "default_stun_a" {
    count = var.config.stun_port != "" ? 1 : 0
    name   = "stun"
    domain = digitalocean_domain.default.name
    type   = "A"
    ttl    = "300"
    value  = local.dns_lead
}

resource "digitalocean_record" "default_cname" {
    count = length(compact(flatten(local.cname_aliases)))
    name   = compact(flatten(local.cname_aliases))[count.index]
    domain = digitalocean_domain.default.name
    type   = "CNAME"
    ttl    = "300"
    value  = "${var.config.root_domain_name}."
}

resource "digitalocean_record" "default_cname_dev" {
    count = length(compact(flatten(local.cname_dev_aliases)))
    name   = compact(flatten(local.cname_dev_aliases))[count.index]
    domain = digitalocean_domain.default.name
    type   = "CNAME"
    ttl    = "300"
    value  = "${var.config.root_domain_name}."
}

resource "digitalocean_record" "default_a_admin" {
    count = length(compact(var.config.admin_arecord_aliases))
    name   = compact(flatten(var.config.admin_arecord_aliases))[count.index]
    domain = digitalocean_domain.default.name
    type   = "A"
    ttl    = "300"
    value  = local.has_admin ? local.dns_admin : local.dns_lead
}

resource "digitalocean_record" "default_a_db" {
    count  = contains(flatten(local.cfg_servers[*].roles), "db") ? length(compact(var.config.db_arecord_aliases)) : 0
    name   = compact(flatten(var.config.db_arecord_aliases))[count.index]
    domain = digitalocean_domain.default.name
    type   = "A"
    ttl    = "300"
    value  = local.dns_db
}

resource "digitalocean_record" "default_a_leader" {
    count  = contains(flatten(local.cfg_servers[*].roles), "lead") ? length(compact(var.config.leader_arecord_aliases)) : 0
    name   = compact(flatten(var.config.leader_arecord_aliases))[count.index]
    domain = digitalocean_domain.default.name
    type   = "A"
    ttl    = "300"
    value  = local.dns_lead
}

resource "digitalocean_record" "default_a_leader_root" {
    count  = contains(flatten(local.cfg_servers[*].roles), "lead") ? 1 : 0
    name   = "@"
    domain = digitalocean_domain.default.name
    type   = "A"
    ttl    = "300"
    value  = local.dns_lead
}

resource "digitalocean_record" "additional_ssl" {
    count  = contains(flatten(local.cfg_servers[*].roles), "lead") ? length(var.config.additional_ssl) : 0
    name   = lookup( element(var.config.additional_ssl, count.index), "subdomain_name")
    domain = digitalocean_domain.default.name
    type   = "CNAME"
    ttl    = "300"
    value  = "${var.config.root_domain_name}."
}

resource "digitalocean_record" "misc_cname" {
    for_each = {
        for ind, domain in local.cname_misc_aliases :
        "${domain.subdomainname}" => domain
    }
    name   = each.value.subdomainname
    domain = digitalocean_domain.default.name
    type   = "CNAME"
    ttl    = "300"
    value  = "${each.value.alias}."
}
