resource "aws_instance" "main" {
    # TODO: total of all counts
    count = var.active_env_provider == "aws" ? length(var.servers) : 0
    depends_on = [aws_internet_gateway.igw]
    key_name = var.aws_key_name
    ami = var.use_packer_image || var.servers[count.index].image == "" ? var.packer_image_id : var.servers[count.index].image
    instance_type = var.servers[count.index].size

    tags = {
        Name = "${var.server_name_prefix}-${var.region}-${local.server_names[count.index]}-${substr(uuid(), 0, 4)}"
        Roles = join(",", var.servers[count.index].roles)
    }
    lifecycle {
        ignore_changes= [ tags ]
    }

    root_block_device {
        volume_size = var.servers[count.index].aws_volume_size
    }

    subnet_id              = aws_subnet.public_subnet.id

    vpc_security_group_ids = compact([
        aws_security_group.default_ports.id,
        aws_security_group.ext_remote.id,

        contains(var.servers[count.index].roles, "admin") ? aws_security_group.admin_ports.id : "",
        contains(var.servers[count.index].roles, "lead") ? aws_security_group.app_ports.id : "",

        contains(var.servers[count.index].roles, "db") ? aws_security_group.db_ports.id : "",
        contains(var.servers[count.index].roles, "db") ? aws_security_group.ext_db.id : "",
    ])

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

### Some sizes for reference
# variable "aws_admin_instance_type" { default = "t3a.large" }
# variable "aws_leader_instance_type" { default = "t3a.small" }
# variable "aws_db_instance_type" { default = "t3a.micro" }
