resource "aws_instance" "main" {
    # TODO: total of all counts
    count = var.active_env_provider == "aws" ? length(var.servers) : 0
    depends_on = [aws_internet_gateway.igw]
    key_name = var.aws_key_name
    ami = var.servers[count.index].image == "" ? var.packer_image_id : var.servers[count.index].image
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

    # Review moving to a create_before_destroy provisioner in admin_nginx
    provisioner "file" {
        content = <<-EOF

            IS_LEAD=${contains(var.servers[count.index].roles, "lead") ? "true" : ""}

            if [ "$IS_LEAD" = "true" ]; then
                docker service update --constraint-add "node.hostname!=${self.tags.Name}" proxy_main
                docker service update --constraint-rm "node.hostname!=${self.tags.Name}" proxy_main
            fi

        EOF
        destination = "/tmp/dockerconstraint.sh"
        connection {
            host     = self.public_ip
            type     = "ssh"
            user     = "root"
        }
    }

    # Review moving to a create_before_destroy provisioner in admin_nginx
    provisioner "file" {
        content = <<-EOF

            IS_LEAD=${contains(var.servers[count.index].roles, "lead") ? "true" : ""}

            if [ "$IS_LEAD" = "true" ]; then
                sed -i "s|${self.private_ip}|${aws_instance.main[0].private_ip}|" /etc/nginx/conf.d/proxy.conf
                gitlab-ctl reconfigure
            fi

        EOF
        destination = "/tmp/changeip.sh"
        connection {
            host     = aws_instance.main[0].public_ip
            type     = "ssh"
            user     = "root"
        }
    }
    provisioner "file" {
        content = <<-EOF

            if [ "${length(regexall("lead", self.tags.Roles)) > 0}" = "true" ]; then
               docker node update --availability="drain" ${self.tags.Name}
               sleep 20;
               docker node demote ${self.tags.Name}
               sleep 5
               docker swarm leave
               docker swarm leave --force;
               exit 0
           fi
        EOF
        destination = "/tmp/remove.sh"
        connection {
            host     = self.public_ip
            type     = "ssh"
            user     = "root"
        }
    }

    ### NOTE: remote-exec destroy-time provisioners are fragile on "terraform destroy"
    ###       as they fail to connect sometimes
    provisioner "remote-exec" {
        when = destroy
        inline = [
            "chmod +x /tmp/dockerconstraint.sh",
            "/tmp/dockerconstraint.sh",
        ]
        connection {
            host     = self.public_ip
            type     = "ssh"
            user     = "root"
        }
    }


    #### Need to figure out how to achieve changing admin nginx by connecting to
    ####  it only at destroy time of this resource without causing a warning
    #### Needs to happen after we've ensured we put all proxies on admin
    #### all proxies admin -> change nginx route ip -> safe to leave swarm
    #### all proxies admin -> change nginx route ip  need to make sure these both happen before we destroy the node
    #### Once docker app proxying happens on nginx instead of docker proxy app, this will be revisted
    #### Add some type of trigger that would only affect this so it only shows up when downsizing

    #### Uncomment this only when downsizing leader servers

    ### NOTE: remote-exec destroy-time provisioners are fragile on "terraform destroy"
    ###       as they fail to connect sometimes
    # provisioner "remote-exec" {
    #     when = destroy
    #     inline = [
    #         "chmod +x /tmp/changeip.sh",
    #         "/tmp/changeip.sh",
    #     ]
    #     connection {
    #         host     = aws_instance.main[0].public_ip
    #         type     = "ssh"
    #         user     = "root"
    #     }
    # }

    ### NOTE: remote-exec destroy-time provisioners are fragile on "terraform destroy"
    ###       as they fail to connect sometimes
    provisioner "remote-exec" {
        when = destroy
        inline = [
            "chmod +x /tmp/remove.sh",
            "/tmp/remove.sh",
        ]
        connection {
            host     = self.public_ip
            type     = "ssh"
            user     = "root"
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
