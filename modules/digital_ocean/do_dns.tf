resource "digitalocean_domain" "additional" {
    for_each = var.config.additional_domains
    name = each.key
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


#resource "digitalocean_record" "default_stun_srv_udp" {
#    count = var.config.stun_port != "" ? 1 : 0
#    name   = "_stun._udp"
#    domain = digitalocean_domain.default.name
#    type   = "SRV"
#    ttl    = "300"
#    priority = "0"
#    weight = "0"
#    port = var.config.stun_port
#    value  = "stun.${var.config.root_domain_name}."
#}

#resource "digitalocean_record" "default_stun_srv_tcp" {
#    count = var.config.stun_port != "" ? 1 : 0
#    name   = "_stun._tcp"
#    domain = digitalocean_domain.default.name
#    type   = "SRV"
#    ttl    = "300"
#    priority = "0"
#    weight = "0"
#    port = var.config.stun_port
#    value  = "stun.${var.config.root_domain_name}."
#}

resource "digitalocean_record" "default_a_offsite" {
    count = length(var.config.offsite_arecord_aliases)
    name   = var.config.offsite_arecord_aliases[count.index].name
    domain = digitalocean_domain.default.name
    type   = "A"
    ttl    = "300"
    value  = var.config.offsite_arecord_aliases[count.index].ip
}

#resource "digitalocean_record" "default_stun_a" {
#    count = var.config.stun_port != "" ? 1 : 0
#    name   = "stun"
#    domain = digitalocean_domain.default.name
#    type   = "A"
#    ttl    = "300"
#    #value  = local.use_lb || local.use_kube_managed_lb ? digitalocean_loadbalancer.main[0].ip : local.dns_lead
#    value  = digitalocean_loadbalancer.main[0].ip
#}

resource "digitalocean_record" "cname" {
    for_each = {
        for ind, record in compact(var.config.cname_aliases):
        record => record
    }
    name   = each.key
    domain = digitalocean_domain.default.name
    type   = "CNAME"
    ttl    = "300"
    value  = "${var.config.root_domain_name}."
}

#resource "digitalocean_record" "default_a_db" {
#    count  = contains(flatten(local.cfg_servers[*].roles), "db") ? length(compact(var.config.db_arecord_aliases)) : 0
#    name   = compact(flatten(var.config.db_arecord_aliases))[count.index]
#    domain = digitalocean_domain.default.name
#    type   = "A"
#    ttl    = "300"
#    value  = local.dns_db
#}

resource "digitalocean_record" "a_wildcard" {
    name   = "*"
    domain = digitalocean_domain.default.name
    type   = "A"
    ttl    = "300"
    value  = data.digitalocean_loadbalancer.main.ip
}

resource "digitalocean_record" "a_k8s" {
    name   = "*.k8s"
    domain = digitalocean_domain.default.name
    type   = "A"
    ttl    = "300"
    value  = data.digitalocean_loadbalancer.main.ip
}

resource "digitalocean_record" "a_k8s_internal" {
    name   = "*.k8s-internal"
    domain = digitalocean_domain.default.name
    type   = "A"
    ttl    = "300"
    ##TODO:  Not sure how internal will work on managed_kubernetes yet
    ## Feel like an additional internal nginx deployment is how itll work
    ## This is currently used for machines to resolve to pod IPs using their k8s ingress resource
    value  = "127.0.0.1"
}

resource "digitalocean_record" "a_root" {
    name   = "@"
    domain = digitalocean_domain.default.name
    type   = "A"
    ttl    = "300"
    value  = data.digitalocean_loadbalancer.main.ip
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
