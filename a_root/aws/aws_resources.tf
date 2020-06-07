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

    subnet_id              = aws_subnet.public_subnet.id
    vpc_security_group_ids = [
        aws_security_group.default_ports.id,
        aws_security_group.admin_ports.id,
        aws_security_group.ext_remote.id,
    ]

    provisioner "remote-exec" {
        inline = [ "cat /home/ubuntu/.ssh/authorized_keys | sudo tee /root/.ssh/authorized_keys" ]
        connection {
            host     = self.public_ip
            type     = "ssh"
            user     = "ubuntu"
        }
    }

    provisioner "local-exec" {
        when = destroy
        command = <<-EOF
            docker-machine rm ${self.tags.Name} -y;
            exit 0;
        EOF
        on_failure = continue
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

    subnet_id              = aws_subnet.public_subnet.id
    vpc_security_group_ids = [
        aws_security_group.default_ports.id,
        aws_security_group.db_ports.id,
        aws_security_group.ext_remote.id,
        aws_security_group.ext_db.id,
    ]

    provisioner "remote-exec" {
        inline = [ "cat /home/ubuntu/.ssh/authorized_keys | sudo tee /root/.ssh/authorized_keys" ]
        connection {
            host     = self.public_ip
            type     = "ssh"
            user     = "ubuntu"
        }
    }

    provisioner "local-exec" {
        when = destroy
        command = <<-EOF
            docker-machine rm ${self.tags.Name} -y;
            exit 0;
        EOF
        on_failure = continue
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

    subnet_id              = aws_subnet.public_subnet.id
    vpc_security_group_ids = [
        aws_security_group.default_ports.id,
        aws_security_group.app_ports.id,
        aws_security_group.ext_remote.id,
    ]

    provisioner "remote-exec" {
        inline = [ "cat /home/ubuntu/.ssh/authorized_keys | sudo tee /root/.ssh/authorized_keys" ]
        connection {
            host     = self.public_ip
            type     = "ssh"
            user     = "ubuntu"
        }
    }

    provisioner "local-exec" {
        when = destroy
        command = <<-EOF
            docker-machine rm ${self.tags.Name} -y;
            exit 0;
        EOF
        on_failure = continue
    }
}
