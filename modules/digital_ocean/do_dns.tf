
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

resource "digitalocean_record" "default_stun_a" {
    count = var.config.stun_port != "" ? 1 : 0
    name   = "stun"
    domain = digitalocean_domain.default.name
    type   = "A"
    ttl    = "300"
    value  = element(slice(local.lead_server_ips, 0, 1), 0)
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
    value  = element(slice(local.admin_server_ips, 0, 1), 0)
}

resource "digitalocean_record" "default_a_db" {
    count = length(compact(var.config.db_arecord_aliases))
    name   = compact(flatten(var.config.db_arecord_aliases))[count.index]
    domain = digitalocean_domain.default.name
    type   = "A"
    ttl    = "300"
    value  = element(slice(local.db_server_ips, 0, 1), 0)
}

resource "digitalocean_record" "default_a_leader" {
    count = length(compact(var.config.leader_arecord_aliases))
    name   = compact(flatten(var.config.leader_arecord_aliases))[count.index]
    domain = digitalocean_domain.default.name
    type   = "A"
    ttl    = "300"
    # If ip matches an admin, go with admin ip or lead ip.
    # Atm choosing first lead ip due to docker proxy service listening port dependent on where it was originally launched
    # Make sure this only points to leader ip after it's joined the swarm, if we cant guarantee, dont change
    value  = element(slice(local.lead_server_ips, 0, 1), 0)

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

resource "digitalocean_record" "default_a_leader_root" {
    count = 1
    name   = "@"
    domain = digitalocean_domain.default.name
    type   = "A"
    ttl    = "300"
    value  = element(slice(local.lead_server_ips, 0, 1), 0)
    # records = slice([
    #     for SERVER in aws_instance.main[*]:
    #     SERVER.public_ip
    #     if length(regexall("lead", SERVER.tags.Roles)) > 0
    # ], 0, 1)
}
