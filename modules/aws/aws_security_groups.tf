# TODO: Amazon limits number of security groups for each network interface to 5
# To increase that limit (have not tested):
# https://aws.amazon.com/premiumsupport/knowledge-center/increase-security-group-rule-limit/
# Appears it needs a support case to increase the limit.
# Under "Limit type": VPC
# Choose region then "Limit": Number of security groups per Interface

# As long as the groups are added at creation you can have 6+ but cannot ADD a 6th after instance created
# Long term goal I guess is no more than 5 groups available

resource "aws_security_group" "db_ports" {
    name = "${local.vpc_name}_db_sg"
    vpc_id = aws_vpc.terraform_vpc.id
    tags = {
        Name = "${local.vpc_name}_db_sg"
    }

    ingress {
        description = "postgresql"
        from_port   = 5432
        to_port     = 5432
        cidr_blocks = [var.config.cidr_block]
        protocol    = "tcp"
    }
    ingress {
        description = "redis"
        from_port   = 6379
        to_port     = 6379
        cidr_blocks = [var.config.cidr_block]
        protocol    = "tcp"
    }
    ingress {
        description = "mongo"
        from_port   = 27017
        to_port     = 27017
        cidr_blocks = [var.config.cidr_block]
        protocol    = "tcp"
    }

    lifecycle {
        create_before_destroy = true
    }

}

resource "aws_security_group" "app_ports" {
    name = "${local.vpc_name}_app_sg"
    vpc_id = aws_vpc.terraform_vpc.id
    tags = {
        Name = "${local.vpc_name}_app_sg"
    }

    # If we ever seperate 80/443 to external load balancers we can move to diff group
    ingress {
        description = "http"
        from_port   = 80
        to_port     = 80
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "tcp"
    }
    ingress {
        description = "https"
        from_port   = 443
        to_port     = 443
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "tcp"
    }
    ingress {
        description = "http"
        from_port   = 8085
        to_port     = 8085
        cidr_blocks = [var.config.cidr_block]
        protocol    = "tcp"
    }
    ingress {
        description = "https"
        from_port   = 4433
        to_port     = 4433
        cidr_blocks = [var.config.cidr_block]
        protocol    = "tcp"
    }

    # App/Api
    ingress {
        description = "Docker Swarm TCP2"
        from_port   = 2377
        to_port     = 2377
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "tcp"
    }
    ingress {
        description = "Docker Swarm TCP1"
        from_port   = 7946
        to_port     = 7946
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "tcp"
    }
    ingress {
        description = "Docker Swarm UDP2"
        from_port   = 4789
        to_port     = 4789
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "udp"
    }
    ingress {
        description = "Docker Swarm UDP1"
        from_port   = 7946
        to_port     = 7946
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "udp"
    }
    ingress {
        description = "Docker Bridge"
        from_port   = 0
        to_port     = 65535
        cidr_blocks = ["172.16.0.0/12"]
        protocol    = "tcp"
    }
    # We allow all ports by default for user, but this will ensure we can at least
    #  make a docker-machine connection even if that rule is deleted
    ingress {
        description = "Docker Machine (user)"
        from_port   = 2376
        to_port     = 2376
        cidr_blocks = ["${var.config.docker_machine_ip}/32"]
        protocol    = "tcp"
    }

    ingress {
        description = "Kubernetes"
        from_port   = 30000                   ## *Purpose* NodePort Services†
        to_port     = 32767
        cidr_blocks = [var.config.cidr_block] ## Probably this setting once we setup dns/ingress
        #cidr_blocks = ["0.0.0.0/0"]           ## Debugging
        protocol    = "tcp"                   ## *Used By*  All
    }

    #ingress {
    #    description = "btcpay"
    #    from_port   = 6080
    #    to_port     = 6080
    #    cidr_blocks = [var.config.cidr_block]
    #    protocol    = "tcp"
    #}

    # STUN
    dynamic "ingress" {
        for_each = {
            for key, value in var.stun_protos:
            key => value
            if var.config.stun_port != ""
        }
        content {
            description = "Stun: ${ingress.value}"
            from_port   = var.config.stun_port
            to_port     = var.config.stun_port
            cidr_blocks = ["0.0.0.0/0"]
            protocol    = ingress.value
        }
    }

    lifecycle {
        create_before_destroy = true
    }
}


resource "aws_security_group" "admin_ports" {
    name = "${local.vpc_name}_admin_sg"
    vpc_id = aws_vpc.terraform_vpc.id
    tags = {
        Name = "${local.vpc_name}_admin_sg"
    }

    ingress {
        description = "http"
        from_port   = 80
        to_port     = 80
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "tcp"
    }
    ingress {
        description = "https"
        from_port   = 443
        to_port     = 443
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "tcp"
    }

    ingress {
        description = "LetsEncrypt"
        from_port   = 7080
        to_port     = 7080
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "tcp"
    }

    ingress {
        description = "Loki"
        from_port   = 3100
        to_port     = 3100
        cidr_blocks = [var.config.cidr_block]
        protocol    = "tcp"
    }

    ingress {
        description = "Kubernetes api"          ## *Purpose* Kubernetes API server
        from_port   = 6443
        to_port     = 6443
        cidr_blocks = [var.config.cidr_block]   ## Only vpc (most secure, but need individual ip access for kubectl)
        #cidr_blocks = ["0.0.0.0/0"]             ## Allow outside private vpc (best in team/group setting or have bastion host)
        protocol    = "tcp"                     ## *Used By* All
    }
    ingress {
        description = "Kubernetes etcd"        ## *Purpose* etcd server client API
        from_port   = 2379
        to_port     = 2380
        cidr_blocks = [var.config.cidr_block]  ## Might be only needed between control nodes
        #cidr_blocks = ["0.0.0.0/0"]            ## Debugging
        protocol    = "tcp"                    ## *Used By* kube-apiserver, etcd
    }
    ingress {
        description = "Kubernetes controller"  ## *Purpose* kubelet API,kube-scheduler,kube-controller-manager
        from_port   = 10250
        to_port     = 10252
        cidr_blocks = [var.config.cidr_block]  ## Might be only needed between control nodes
        #cidr_blocks = ["0.0.0.0/0"]            ## Debugging
        protocol    = "tcp"                    ## *Used By* Self/Control Plane
    }

    lifecycle {
        create_before_destroy = true
    }
}


resource "aws_security_group" "default_ports" {
    name = "${local.vpc_name}_default_sg"
    vpc_id = aws_vpc.terraform_vpc.id
    tags = {
        Name = "${local.vpc_name}_default_sg"
    }

    ingress {
        description = "ssh"
        from_port   = 22
        to_port     = 22
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "tcp"
    }
    ingress {
        description = "localhost1"
        from_port   = 0
        to_port     = 65535
        cidr_blocks = ["127.0.0.0/20"]
        protocol    = "tcp"
    }
    ingress {
        description = "localhost2"
        from_port   = 0
        to_port     = 65535
        cidr_blocks = ["192.168.0.0/20"]
        protocol    = "tcp"
    }

    # Default allow terraform user to every port
    ingress {
        description = "All User"
        from_port   = 0
        to_port     = 65535
        cidr_blocks = ["${var.config.docker_machine_ip}/32"]
        protocol    = "tcp"
    }
    ingress {
        description = "All User UDP"
        from_port   = 0
        to_port     = 65535
        cidr_blocks = ["${var.config.docker_machine_ip}/32"]
        protocol    = "udp"
    }

    # Consul communication between vpc
    ingress {
        description = "consul1"
        from_port   = 8300
        to_port     = 8302
        cidr_blocks = [var.config.cidr_block]
        protocol    = "tcp"
    }
    ingress {
        description = "consuludp1"
        from_port   = 8300
        to_port     = 8302
        cidr_blocks = [var.config.cidr_block]
        protocol    = "udp"
    }
    ingress {
        description = "consul2"
        from_port   = 8400
        to_port     = 8400
        cidr_blocks = [var.config.cidr_block]
        protocol    = "tcp"
    }
    ingress {
        description = "consul3"
        from_port   = 8500
        to_port     = 8500
        cidr_blocks = [var.config.cidr_block]
        protocol    = "tcp"
    }
    ingress {
        description = "consul4"
        from_port   = 8600
        to_port     = 8600
        cidr_blocks = [var.config.cidr_block]
        protocol    = "tcp"
    }

    #System metrics
    ingress {
        description = "prometheus"
        from_port   = 9100
        to_port     = 9100
        cidr_blocks = [var.config.cidr_block]
        protocol    = "tcp"
    }


    #kubernetes
    ingress {
        description = "Kubernetes api"          ## *Purpose* Kubernetes API server
        from_port   = 10250                     ## *Purpose* kubelet API - `kubectl exec/logs`
        to_port     = 10250
        cidr_blocks = [var.config.cidr_block]  ## Nodes "Internal IP" must be in vpc to work
        #cidr_blocks = ["0.0.0.0/0"]            ## Debugging or? If "Internal IP" is not set to vpc
        protocol    = "tcp"                    ## *Used By*  Self, Control plane
    }
    ingress {
        description = "Kubernetes flannel CNI"
        from_port   = 8472                     ## *Purpose* flannel CNI 
        to_port     = 8472
        cidr_blocks = [var.config.cidr_block]  ## Needs vpc iface added to flannels DaemonSet args
        #cidr_blocks = ["0.0.0.0/0"]            ## Debugging
        protocol    = "udp"                    ## *Used By*  worker
    }

    ## NOTE: Untested - ICMP for network/ping
    #ingress {
    #    description = "All icmp"
    #    from_port   = 0
    #    to_port     = 0
    #    cidr_blocks = ["0.0.0.0/0"]
    #    protocol    = "icmp"
    #}
    #egress {
    #    description = "All icmp"
    #    from_port   = 0
    #    to_port     = 0
    #    cidr_blocks = ["0.0.0.0/0"]
    #    protocol    = "icmp"
    #}

    egress {
        description = "All traffic"
        from_port   = 0
        to_port     = 0
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "-1"
    }

    lifecycle {
        create_before_destroy = true
    }
}

resource "aws_security_group" "ext_db" {
    name = "${local.vpc_name}_ext_db_sg"
    vpc_id = aws_vpc.terraform_vpc.id
    tags = {
        Name = "${local.vpc_name}_ext_db_sg"
    }

    ingress {
        description = "postgresql"
        from_port   = 5432
        to_port     = 5432
        cidr_blocks = [
            for OBJ in var.config.app_ips:
            "${OBJ.ip}/32"
        ]
        protocol    = "tcp"
    }
    ingress {
        description = "redis"
        from_port   = 6379
        to_port     = 6379
        cidr_blocks = [
            for OBJ in var.config.app_ips:
            "${OBJ.ip}/32"
        ]
        protocol    = "tcp"
    }
    ingress {
        description = "mongo"
        from_port   = 27017
        to_port     = 27017
        cidr_blocks = [
            for OBJ in var.config.app_ips:
            "${OBJ.ip}/32"
        ]
        protocol    = "tcp"
    }

    lifecycle {
        create_before_destroy = true
    }
}

resource "aws_security_group" "ext_remote" {
    name = "${local.vpc_name}_ext_remote_sg"
    vpc_id = aws_vpc.terraform_vpc.id
    tags = {
        Name = "${local.vpc_name}_ext_remote_sg"
    }

    ingress {
        description = "All Ports"
        from_port   = 0
        to_port     = 65535
        cidr_blocks = [
            for OBJ in var.config.station_ips:
            "${OBJ.ip}/32"
        ]
        protocol    = "tcp"
    }

    lifecycle {
        create_before_destroy = true
    }
}
