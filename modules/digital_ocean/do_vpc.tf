
locals {
    vpc_name = "${var.server_name_prefix}-vpc"
}

# query/create vpc
resource "digitalocean_vpc" "terraform_vpc" {
    name          = local.vpc_name
    region        = var.region
    ip_range      = var.cidr_block
}

resource "digitalocean_firewall" "db" {
    name = "${local.vpc_name}-db"

    droplet_ids = local.db_server_ids

    # "postgresql"
    inbound_rule  {
        protocol    = "tcp"
        port_range   = 5432
        source_addresses = [var.cidr_block]
    }

    # "redis"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 6379
        source_addresses = [var.cidr_block]
    }

    # "mongo"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 27017
        source_addresses = [var.cidr_block]
    }

    lifecycle {
        create_before_destroy = true
    }

}



resource "digitalocean_firewall" "app" {
    name = "${local.vpc_name}-app"

    droplet_ids = local.lead_server_ids

    # If we ever seperate 80/443 to external load balancers we can move to diff group
    # "http"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 80
        source_addresses = ["0.0.0.0/0"]
    }

    # "https"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 443
        source_addresses = ["0.0.0.0/0"]
    }

    # "http"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 8085
        source_addresses = [var.cidr_block]
    }

    # "https"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 4433
        source_addresses = [var.cidr_block]
    }

    # App/Api
    # "Docker Swarm TCP2"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 2377
        source_addresses = ["0.0.0.0/0"]
    }

    # "Docker Swarm TCP1"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 7946
        source_addresses = ["0.0.0.0/0"]
    }

    # "Docker Swarm UDP2"
    inbound_rule {
        protocol    = "udp"
        port_range   = 4789
        source_addresses = ["0.0.0.0/0"]
    }

    # "Docker Swarm UDP1"
    inbound_rule {
        protocol    = "udp"
        port_range   = 7946
        source_addresses = ["0.0.0.0/0"]
    }

    # "Docker Bridge"
    inbound_rule {
        protocol    = "tcp"
        port_range   = "1-65535"
        source_addresses = ["172.16.0.0/12"]
    }

    # We allow all ports by default for user, but this will ensure we can at least
    #  make a docker-machine connection even if that rule is deleted
    # "Docker Machine (user)"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 2376
        source_addresses = ["${var.docker_machine_ip}/32"]
    }

    # "btcpay"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 6080
        source_addresses = [var.cidr_block]
    }

    # STUN
    dynamic "inbound_rule" {
        for_each = {
            for key, value in var.stun_protos:
            key => value
            if var.stun_port != ""
        }
        # description = "Stun: ${ingress.value}"
        content {
            protocol    = inbound_rule.value
            port_range   = var.stun_port
            source_addresses = ["0.0.0.0/0"]
        }
    }

    lifecycle {
        create_before_destroy = true
    }
}


resource "digitalocean_firewall" "admin" {
    name = "${local.vpc_name}-admin"

    droplet_ids = local.admin_server_ids

    # description = "http"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 80
        source_addresses = ["0.0.0.0/0"]
    }
    # description = "https"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 443
        source_addresses = ["0.0.0.0/0"]
    }

    # description = "LetsEncrypt"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 7080
        source_addresses = ["0.0.0.0/0"]
    }

    lifecycle {
        create_before_destroy = true
    }
}



resource "digitalocean_firewall" "default" {
    name = "${local.vpc_name}-default"

    droplet_ids = local.all_server_ids

    # description = "ssh"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 22
        source_addresses = ["0.0.0.0/0"]
    }
    # description = "localhost1"
    inbound_rule {
        protocol    = "tcp"
        port_range   = "1-65535"
        source_addresses = ["127.0.0.0/20"]
    }
    # description = "localhost2"
    inbound_rule {
        protocol    = "tcp"
        port_range   = "1-65535"
        source_addresses = ["192.168.0.0/20"]
    }

    # Default allow terraform user to every port
    # description = "All User"
    inbound_rule {
        protocol    = "tcp"
        port_range   = "1-65535"
        source_addresses = ["${var.docker_machine_ip}/32"]
    }
    # description = "All User UDP"
    inbound_rule {
        protocol    = "udp"
        port_range   = "1-65535"
        source_addresses = ["${var.docker_machine_ip}/32"]
    }

    # Consul communication between vpc
    # description = "consul1"
    inbound_rule {
        protocol    = "tcp"
        port_range   = "8300-8302"
        source_addresses = [var.cidr_block]
    }
    # description = "consuludp1"
    inbound_rule {
        protocol    = "udp"
        port_range   = "8300-8302"
        source_addresses = [var.cidr_block]
    }
    # description = "consul2"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 8400
        source_addresses = [var.cidr_block]
    }
    # description = "consul3"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 8500
        source_addresses = [var.cidr_block]
    }
    # description = "consul4"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 8600
        source_addresses = [var.cidr_block]
    }



    # description = "All traffic tcp"
    outbound_rule {
        port_range   = "1-65535"
        destination_addresses = ["0.0.0.0/0"]
        protocol    = "tcp"
    }
    # description = "All traffic udp"
    outbound_rule {
        port_range   = "1-65535"
        destination_addresses = ["0.0.0.0/0"]
        protocol    = "udp"
    }

    lifecycle {
        create_before_destroy = true
    }
}

resource "digitalocean_firewall" "ext_db" {
    name = "${local.vpc_name}-ext-db"

    droplet_ids = local.db_server_ids

    # description = "postgresql"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 5432
        source_addresses = [
            for OBJ in var.app_ips:
            "${OBJ.ip}/32"
        ]
    }

    # description = "redis"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 6379
        source_addresses = [
            for OBJ in var.app_ips:
            "${OBJ.ip}/32"
        ]
    }

    # description = "mongo"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 27017
        source_addresses = [
            for OBJ in var.app_ips:
            "${OBJ.ip}/32"
        ]
    }

    lifecycle {
        create_before_destroy = true
    }
}

resource "digitalocean_firewall" "ext_remote" {
    name = "${local.vpc_name}-ext-remote"

    droplet_ids = local.all_server_ids

    # description = "All Ports"
    inbound_rule {
        protocol    = "tcp"
        port_range   = "1-65535"
        source_addresses = [
            for OBJ in var.station_ips:
            "${OBJ.ip}/32"
        ]
    }

    lifecycle {
        create_before_destroy = true
    }
}
