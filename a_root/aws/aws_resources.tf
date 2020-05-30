resource "aws_instance" "admin" {
    count = var.active_env_provider == "aws" ? var.admin_servers : 0
    depends_on = [aws_internet_gateway.igw]
    key_name = var.aws_key_name
    ami = var.aws_ami
    # ami = data.aws_ami.ubuntu.id
    instance_type = var.aws_admin_instance_type
    tags = { Name = "${var.server_name_prefix}-${var.region}-admin-${substr(uuid(), 0, 4)}" }
    lifecycle {
        ignore_changes= [ tags ]
    }

    root_block_device {
        volume_size = 30
    }

    associate_public_ip_address = true
    subnet_id              = aws_subnet.public_subnet.id
    vpc_security_group_ids = [aws_security_group.default_ports.id, aws_security_group.admin_ports.id]

    provisioner "remote-exec" {
        inline = [ "cat /home/ubuntu/.ssh/authorized_keys | sudo tee /root/.ssh/authorized_keys" ]
        connection {
            host     = self.public_ip
            type     = "ssh"
            user     = "ubuntu"
        }
    }
}

resource "aws_instance" "build" {
    count = var.active_env_provider == "aws" ? var.build_servers : 0
    key_name = var.aws_key_name
    ami = var.aws_ami
    instance_type = var.aws_build_instance_type
    tags = { Name = "${var.server_name_prefix}-${var.region}-build-${substr(uuid(), 0, 4)}" }
    lifecycle {
        ignore_changes= [ tags ]
    }

    depends_on = [aws_instance.lead, aws_internet_gateway.igw]

    associate_public_ip_address = true
    subnet_id              = aws_subnet.public_subnet.id
    vpc_security_group_ids = [aws_security_group.default_ports.id]

    provisioner "remote-exec" {
        inline = [ "cat /home/ubuntu/.ssh/authorized_keys | sudo tee /root/.ssh/authorized_keys" ]
        connection {
            host     = self.public_ip
            type     = "ssh"
            user     = "ubuntu"
        }
    }
}

resource "aws_instance" "db" {
    count = var.active_env_provider == "aws" ? var.db_servers : 0
    depends_on = [aws_internet_gateway.igw]
    key_name = var.aws_key_name
    ami = var.aws_ami
    instance_type = var.aws_db_instance_type
    tags = { Name = "${var.server_name_prefix}-${var.region}-db-${substr(uuid(), 0, 4)}" }
    lifecycle {
        ignore_changes= [ tags ]
    }

    root_block_device {
        volume_size = 30
    }

    associate_public_ip_address = true
    subnet_id              = aws_subnet.public_subnet.id
    vpc_security_group_ids = [aws_security_group.default_ports.id, aws_security_group.db_ports.id]

    provisioner "remote-exec" {
        inline = [ "cat /home/ubuntu/.ssh/authorized_keys | sudo tee /root/.ssh/authorized_keys" ]
        connection {
            host     = self.public_ip
            type     = "ssh"
            user     = "ubuntu"
        }
    }
}

resource "aws_instance" "dev" {
    count = var.active_env_provider == "aws" ? var.dev_servers : 0
    key_name = var.aws_key_name
    ami = var.aws_ami
    instance_type = var.aws_dev_instance_type
    tags = { Name = "${var.server_name_prefix}-${var.region}-dev-${substr(uuid(), 0, 4)}" }
    lifecycle {
        ignore_changes= [ tags ]
    }

    depends_on = [aws_instance.lead, aws_internet_gateway.igw]

    associate_public_ip_address = true
    subnet_id              = aws_subnet.public_subnet.id
    # Maybe add these for more open server access on a throwaway machine
    # aws_security_group.db_ports.id,
    # aws_security_group.app_ports.id
    vpc_security_group_ids = [
        aws_security_group.default_ports.id,
    ]

    provisioner "remote-exec" {
        inline = [ "cat /home/ubuntu/.ssh/authorized_keys | sudo tee /root/.ssh/authorized_keys" ]
        connection {
            host     = self.public_ip
            type     = "ssh"
            user     = "ubuntu"
        }
    }
}

# TODO: USE MODULO FOR MORE LEADERS
resource "aws_instance" "lead" {
    count = var.active_env_provider == "aws" ? var.leader_servers : 0
    depends_on = [aws_internet_gateway.igw]
    key_name = var.aws_key_name
    ami = var.aws_ami
    # ami = data.aws_ami.ubuntu.id
    instance_type = var.aws_leader_instance_type
    tags = { Name = "${var.server_name_prefix}-${var.region}-lead-${substr(uuid(), 0, 4)}" }
    lifecycle {
        ignore_changes= [ tags ]
    }

    root_block_device {
        volume_size = 20
    }

    associate_public_ip_address = true
    subnet_id              = aws_subnet.public_subnet.id
    vpc_security_group_ids = [aws_security_group.default_ports.id, aws_security_group.app_ports.id]

    provisioner "remote-exec" {
        inline = [ "cat /home/ubuntu/.ssh/authorized_keys | sudo tee /root/.ssh/authorized_keys" ]
        connection {
            host     = self.public_ip
            type     = "ssh"
            user     = "ubuntu"
        }
    }
}

resource "aws_instance" "mongo" {
    count = var.active_env_provider == "aws" ? var.mongo_servers : 0
    depends_on = [aws_internet_gateway.igw]
    key_name = var.aws_key_name
    ami = var.aws_ami
    instance_type = var.aws_mongo_instance_type
    tags = { Name = "${var.server_name_prefix}-${var.region}-mongo-${substr(uuid(), 0, 4)}" }
    lifecycle {
        ignore_changes= [ tags ]
    }

    associate_public_ip_address = true
    subnet_id              = aws_subnet.public_subnet.id
    vpc_security_group_ids = [aws_security_group.default_ports.id, aws_security_group.db_ports.id]

    provisioner "remote-exec" {
        inline = [ "cat /home/ubuntu/.ssh/authorized_keys | sudo tee /root/.ssh/authorized_keys" ]
        connection {
            host     = self.public_ip
            type     = "ssh"
            user     = "ubuntu"
        }
    }
}

resource "aws_instance" "pg" {
    count = var.active_env_provider == "aws" ? var.pg_servers : 0
    depends_on = [aws_internet_gateway.igw]
    key_name = var.aws_key_name
    ami = var.aws_ami
    instance_type = var.aws_pg_instance_type
    tags = { Name = "${var.server_name_prefix}-${var.region}-pg-${substr(uuid(), 0, 4)}" }
    lifecycle {
        ignore_changes= [ tags ]
    }

    associate_public_ip_address = true
    subnet_id              = aws_subnet.public_subnet.id
    vpc_security_group_ids = [aws_security_group.default_ports.id, aws_security_group.db_ports.id]

    provisioner "remote-exec" {
        inline = [ "cat /home/ubuntu/.ssh/authorized_keys | sudo tee /root/.ssh/authorized_keys" ]
        connection {
            host     = self.public_ip
            type     = "ssh"
            user     = "ubuntu"
        }
    }
}


resource "aws_instance" "redis" {
    count = var.active_env_provider == "aws" ? var.redis_servers : 0
    depends_on = [aws_internet_gateway.igw]
    key_name = var.aws_key_name
    ami = var.aws_ami
    instance_type = var.aws_redis_instance_type
    tags = { Name = "${var.server_name_prefix}-${var.region}-redis-${substr(uuid(), 0, 4)}" }
    lifecycle {
        ignore_changes= [ tags ]
    }

    associate_public_ip_address = true
    subnet_id              = aws_subnet.public_subnet.id
    vpc_security_group_ids = [aws_security_group.default_ports.id, aws_security_group.db_ports.id]

    provisioner "remote-exec" {
        inline = [ "cat /home/ubuntu/.ssh/authorized_keys | sudo tee /root/.ssh/authorized_keys" ]
        connection {
            host     = self.public_ip
            type     = "ssh"
            user     = "ubuntu"
        }
    }
}

resource "aws_instance" "web" {
    count = var.active_env_provider == "aws" ? var.web_servers : 0
    key_name = var.aws_key_name
    ami = var.aws_ami
    instance_type = var.aws_web_instance_type
    tags = { Name = "${var.server_name_prefix}-${var.region}-web-${substr(uuid(), 0, 4)}" }
    lifecycle {
        ignore_changes= [ tags ]
    }

    depends_on = [aws_instance.lead, aws_internet_gateway.igw]

    associate_public_ip_address = true
    subnet_id              = aws_subnet.public_subnet.id
    vpc_security_group_ids = [aws_security_group.default_ports.id, aws_security_group.app_ports.id]

    provisioner "remote-exec" {
        inline = [ "cat /home/ubuntu/.ssh/authorized_keys | sudo tee /root/.ssh/authorized_keys" ]
        connection {
            host     = self.public_ip
            type     = "ssh"
            user     = "ubuntu"
        }
    }
}
