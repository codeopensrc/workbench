resource "aws_security_group" "default_ports" {
    name = var.server_name_prefix
    tags = {
        Name = var.server_name_prefix
    }

    ingress {
        description = "ssh"
        from_port   = 22
        to_port     = 22
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "tcp"
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
        description = "postgresql"
        from_port   = 5432
        to_port     = 5432
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "tcp"
    }
    ingress {
        description = "redis"
        from_port   = 6379
        to_port     = 6379
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "tcp"
    }
    ingress {
        description = "mongo"
        from_port   = 27017
        to_port     = 27017
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "tcp"
    }
    ingress {
        description = "consul1"
        from_port   = 8300
        to_port     = 8302
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "tcp"
    }
    ingress {
        description = "consul2"
        from_port   = 8400
        to_port     = 8400
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "tcp"
    }
    ingress {
        description = "consul3"
        from_port   = 8500
        to_port     = 8500
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "tcp"
    }
    ingress {
        description = "consul4"
        from_port   = 8600
        to_port     = 8600
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
        description = "Docker Swarm TCP2"
        from_port   = 2377
        to_port     = 2377
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "tcp"
    }
    ingress {
        description = "Docker Swarm UDP1"
        from_port   = 7946
        to_port     = 7946
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "udp"
    }
    ingress {
        description = "Docker Swarm UDP2"
        from_port   = 4789
        to_port     = 4789
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "udp"
    }
    ingress {
        description = "LetsEncrypt"
        from_port   = 7080
        to_port     = 7080
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "tcp"
    }
    ingress {
        description = "Chef_Http"
        from_port   = 8888
        to_port     = 8888
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "tcp"
    }
    ingress {
        description = "Chef_Https"
        from_port   = 4433
        to_port     = 4433
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "tcp"
    }
    ingress {
        description = "Chef oc_bifrost"
        from_port   = 9683
        to_port     = 9683
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "tcp"
    }
    ingress {
        description = "Docker Bridge"
        from_port   = 0
        to_port     = 65535
        cidr_blocks = ["172.16.0.0/12"]
        protocol    = "tcp"
    }
    ingress {
        description = "localhost1"
        from_port   = 0
        to_port     = 65535
        cidr_blocks = ["127.0.0.0/32"]
        protocol    = "tcp"
    }
    ingress {
        description = "localhost2"
        from_port   = 0
        to_port     = 65535
        cidr_blocks = ["192.168.0.0/20"]
        protocol    = "tcp"
    }
    ingress {
        description = "Docker Machine (user)"
        from_port   = 2376
        to_port     = 2376
        cidr_blocks = ["${var.docker_machine_ip}/32"]
        protocol    = "tcp"
    }
    # Default allow terraform user to every port as well
    ingress {
        description = "All User"
        from_port   = 0
        to_port     = 65535
        cidr_blocks = ["${var.docker_machine_ip}/32"]
        protocol    = "tcp"
    }
    # Allow all traffic out
    egress {
        description = "All traffic"
        from_port   = 0
        to_port     = 0
        cidr_blocks = ["0.0.0.0/0"]
        protocol    = "-1"
    }



    # ingress {
    #     description = "Unicorn"
    #     from_port   = 8080
    #     to_port     = 8080
    #     cidr_blocks = ["0.0.0.0/0"]
    #     protocol    = "tcp"
    # }

}
