
locals {
    vpc_name = "${var.config.server_name_prefix}-vpc"
}

# query/create vpc
resource "digitalocean_vpc" "terraform_vpc" {
    name          = local.vpc_name
    region        = var.config.region
    ip_range      = var.config.cidr_block
}

resource "digitalocean_firewall" "db" {
    name = "${local.vpc_name}-db"

    droplet_ids = data.digitalocean_droplets.db.droplets[*].id

    # description = "ssh"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 22
        source_addresses = ["0.0.0.0/0"]
    }
    # "postgresql"
    inbound_rule  {
        protocol    = "tcp"
        port_range   = 5432
        source_addresses = [var.config.cidr_block]
    }

    # "redis"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 6379
        source_addresses = [var.config.cidr_block]
    }

    # "mongo"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 27017
        source_addresses = [var.config.cidr_block]
    }

    lifecycle {
        create_before_destroy = true
    }

}



resource "digitalocean_firewall" "app" {
    name = "${local.vpc_name}-app"

    droplet_ids = data.digitalocean_droplets.lead.droplets[*].id

    # description = "ssh"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 22
        source_addresses = ["0.0.0.0/0"]
    }
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

    # "http" when admin + lead same server. see module.docker
    inbound_rule {
        protocol    = "tcp"
        port_range   = 8085
        source_addresses = [var.config.cidr_block]
    }

    # "https" when admin + lead same server. see module.docker
    inbound_rule {
        protocol    = "tcp"
        port_range   = 4433
        source_addresses = [var.config.cidr_block]
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
        port_range   = "all"
        source_addresses = ["172.16.0.0/12"]
    }

    # description = "kubernetes"
    inbound_rule {
        protocol    = "tcp"                         ## *Used By*  All
        port_range   = "30000-32767"                ## *Purpose* NodePort Services†
        source_addresses = [var.config.cidr_block] ## Probably this setting once we setup dns/ingress
        #source_addresses = ["0.0.0.0/0"]           ## Debugging
    }

    ## "btcpay"
    #inbound_rule {
    #    protocol    = "tcp"
    #    port_range   = 6080
    #    source_addresses = [var.config.cidr_block]
    #}

    # STUN
    dynamic "inbound_rule" {
        for_each = {
            for key, value in var.stun_protos:
            key => value
            if var.config.stun_port != ""
        }
        # description = "Stun: ${ingress.value}"
        content {
            protocol    = inbound_rule.value
            port_range   = var.config.stun_port
            source_addresses = ["0.0.0.0/0"]
        }
    }

    lifecycle {
        create_before_destroy = true
    }
}


resource "digitalocean_firewall" "admin" {
    name = "${local.vpc_name}-admin"

    droplet_ids = local.admin_servers > 0 ? data.digitalocean_droplets.admin.droplets[*].id : data.digitalocean_droplets.lead.droplets[*].id

    # description = "ssh"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 22
        source_addresses = ["0.0.0.0/0"]
    }
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

    # description = "Loki"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 3100
        source_addresses = [var.config.cidr_block]
    }

    # description = "Kubernetes"
    inbound_rule {
        protocol    = "tcp"                         ## *Used By* All
        port_range   = 6443                         ## *Purpose* Kubernetes API server
        source_addresses = [var.config.cidr_block]  ## Only vpc (most secure, but need individual ip access for kubectl)
        #source_addresses = ["0.0.0.0/0"]            ## Allow outside private vpc (best in team/group setting or have bastion host)
    }
    # description = "Kubernetes"
    inbound_rule {
        protocol    = "tcp"                        ## *Used By* kube-apiserver, etcd
        port_range   = "2379-2380"                 ## *Purpose* etcd server client API
        source_addresses = [var.config.cidr_block] ## Might be only needed between control nodes
        #source_addresses = ["0.0.0.0/0"]           ## Debugging
    }
    # description = "Kubernetes"
    inbound_rule {
        protocol    = "tcp"                        ## *Used By* Self/Control Plane
        port_range   = "10250-10252"               ## *Purpose* kubelet API,kube-scheduler,kube-controller-manager
        source_addresses = [var.config.cidr_block] ## Might be only needed between control nodes
        #source_addresses = ["0.0.0.0/0"]           ## Debugging
    }

    lifecycle {
        create_before_destroy = true
    }
}



resource "digitalocean_firewall" "default" {
    name = "${local.vpc_name}-default"

    droplet_ids = concat(data.digitalocean_droplets.admin.droplets[*].id, data.digitalocean_droplets.lead.droplets[*].id, data.digitalocean_droplets.db.droplets[*].id, data.digitalocean_droplets.build.droplets[*].id)

    # description = "ssh"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 22
        source_addresses = ["0.0.0.0/0"]
    }
    # description = "localhost1"
    inbound_rule {
        protocol    = "tcp"
        port_range   = "all"
        source_addresses = ["127.0.0.0/20"]
    }
    # description = "localhost2"
    inbound_rule {
        protocol    = "tcp"
        port_range   = "all"
        source_addresses = ["192.168.0.0/20"]
    }

    # Default allow terraform user to every port
    # description = "All User"
    inbound_rule {
        protocol    = "tcp"
        port_range   = "all"
        source_addresses = ["${var.config.docker_machine_ip}/32"]
    }
    # description = "All User UDP"
    inbound_rule {
        protocol    = "udp"
        port_range   = "all"
        source_addresses = ["${var.config.docker_machine_ip}/32"]
    }

    # Consul communication between vpc
    # description = "consul1"
    inbound_rule {
        protocol    = "tcp"
        port_range   = "8300-8302"
        source_addresses = [var.config.cidr_block]
    }
    # description = "consuludp1"
    inbound_rule {
        protocol    = "udp"
        port_range   = "8300-8302"
        source_addresses = [var.config.cidr_block]
    }
    # description = "consul2"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 8400
        source_addresses = [var.config.cidr_block]
    }
    # description = "consul3"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 8500
        source_addresses = [var.config.cidr_block]
    }
    # description = "consul4"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 8600
        source_addresses = [var.config.cidr_block]
    }


    # description = "prometheus"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 9100
        source_addresses = [var.config.cidr_block]
    }

    # description = "kubernetes"
    inbound_rule {
        protocol    = "tcp"                         ## *Used By*  Self, Control plane
        port_range   = 10250                        ## *Purpose* kubelet API - `kubectl exec/logs`
        source_addresses = [var.config.cidr_block]  ## Nodes "Internal IP" must be in vpc to work
        #source_addresses = ["0.0.0.0/0"]           ## Debugging or? If "Internal IP" is not set to vpc
    }
    # description = "kubernetes"
    inbound_rule {
        protocol    = "udp"                         ## *Used By*  worker
        port_range   = 8472                         ## *Purpose* flannel CNI 
        source_addresses = [var.config.cidr_block]  ## Needs vpc iface added to flannels DaemonSet args
        #source_addresses = ["0.0.0.0/0"]           ## Debugging
    }



    # description = "All ICMP"
    inbound_rule {
        protocol         = "icmp"
        source_addresses = ["0.0.0.0/0", "::/0"]
    }
    # description = "All ICMP"
    outbound_rule {
        destination_addresses = ["0.0.0.0/0", "::/0"]
        protocol    = "icmp"
    }
    # description = "All traffic tcp"
    outbound_rule {
        port_range   = "all"
        destination_addresses = ["0.0.0.0/0"]
        protocol    = "tcp"
    }
    # description = "All traffic udp"
    outbound_rule {
        port_range   = "all"
        destination_addresses = ["0.0.0.0/0"]
        protocol    = "udp"
    }

    lifecycle {
        create_before_destroy = true
    }
}

resource "digitalocean_firewall" "ext_db" {
    name = "${local.vpc_name}-ext-db"

    droplet_ids = data.digitalocean_droplets.db.droplets[*].id

    # description = "postgresql"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 5432
        source_addresses = [
            for OBJ in var.config.app_ips:
            "${OBJ.ip}/32"
        ]
    }

    # description = "redis"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 6379
        source_addresses = [
            for OBJ in var.config.app_ips:
            "${OBJ.ip}/32"
        ]
    }

    # description = "mongo"
    inbound_rule {
        protocol    = "tcp"
        port_range   = 27017
        source_addresses = [
            for OBJ in var.config.app_ips:
            "${OBJ.ip}/32"
        ]
    }

    lifecycle {
        create_before_destroy = true
    }
}

resource "digitalocean_firewall" "ext_remote" {
    name = "${local.vpc_name}-ext-remote"

    droplet_ids = concat(data.digitalocean_droplets.admin.droplets[*].id, data.digitalocean_droplets.lead.droplets[*].id, data.digitalocean_droplets.db.droplets[*].id, data.digitalocean_droplets.build.droplets[*].id)

    # description = "All Ports"
    inbound_rule {
        protocol    = "tcp"
        port_range   = "all"
        source_addresses = [
            for OBJ in var.config.station_ips:
            "${OBJ.ip}/32"
        ]
    }

    lifecycle {
        create_before_destroy = true
    }
}
