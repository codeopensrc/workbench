data "digitalocean_images" "latest" {
    filter {
        key    = "name"
        values = [ local.do_image_name ]
        all = true
    }
    filter {
        key    = "regions"
        values = [ var.config.do_region ]
        all = true
    }
    filter {
        key    = "private"
        values = ["true"]
        all = true
    }
    sort {
        key       = "created"
        direction = "desc"
    }
}

module "packer" {
    source             = "../packer"
    build = length(data.digitalocean_images.latest.images) >= 1 ? false : true

    active_env_provider = var.config.active_env_provider

    aws_access_key = var.config.aws_access_key
    aws_secret_key = var.config.aws_secret_key
    aws_region = var.config.aws_region
    aws_key_name = var.config.aws_key_name
    aws_instance_type = "t2.medium"

    do_token = var.config.do_token
    digitalocean_region = var.config.do_region
    digitalocean_image_size = "s-2vcpu-4gb"

    packer_config = var.config.packer_config
}

data "digitalocean_images" "output" {
    depends_on = [ module.packer ]
    filter {
        key    = "name"
        values = [ local.do_image_name ]
        all = true
    }
    filter {
        key    = "regions"
        values = [ var.config.do_region ]
        all = true
    }
    filter {
        key    = "private"
        values = ["true"]
        all = true
    }
    sort {
        key       = "created"
        direction = "desc"
    }
}

resource "digitalocean_droplet" "main" {
    count = length(var.config.servers)
    name     = "${var.config.server_name_prefix}-${var.config.region}-${local.server_names[count.index]}-${substr(uuid(), 0, 4)}"
    image    = var.config.servers[count.index].image == "" ? data.digitalocean_images.output.images[0].id : var.config.servers[count.index].image
    region   = var.config.region
    size     = var.config.servers[count.index].size["digital_ocean"]
    ssh_keys = [var.config.do_ssh_fingerprint]
    tags = flatten([
        "${var.config.server_name_prefix}-${var.config.region}-${local.server_names[count.index]}-${substr(uuid(), 0, 4)}",
        var.config.servers[count.index].roles
    ])

    lifecycle {
        ignore_changes = [name, tags]
    }

    vpc_uuid = digitalocean_vpc.terraform_vpc.id


    provisioner "remote-exec" {
        inline = [ "cat /home/ubuntu/.ssh/authorized_keys | sudo tee /root/.ssh/authorized_keys" ]
        connection {
            host     = self.ipv4_address
            type     = "ssh"
            user     = "root"
            private_key = file(var.config.local_ssh_key_file)
        }
    }

    provisioner "file" {
        content = <<-EOF

            IS_LEAD=${contains(var.config.servers[count.index].roles, "lead") ? "true" : ""}

            if [ "$IS_LEAD" = "true" ]; then
                docker service update --constraint-add "node.hostname!=${self.name}" proxy_main
                docker service update --constraint-rm "node.hostname!=${self.name}" proxy_main
            fi

        EOF
        destination = "/tmp/dockerconstraint.sh"
        connection {
            host     = self.ipv4_address
            type     = "ssh"
            user     = "root"
            private_key = file(var.config.local_ssh_key_file)
        }
    }
    provisioner "file" {
        content = <<-EOF

            IS_LEAD=${contains(var.config.servers[count.index].roles, "lead") ? "true" : ""}

            if [ "$IS_LEAD" = "true" ]; then
                sed -i "s|${self.ipv4_address_private}|${digitalocean_droplet.main[0].ipv4_address_private}|" /etc/nginx/conf.d/proxy.conf
                gitlab-ctl reconfigure
            fi

        EOF
        destination = "/tmp/changeip-${self.name}.sh"
        connection {
            host     = digitalocean_droplet.main[0].ipv4_address
            type     = "ssh"
            user     = "root"
            private_key = file(var.config.local_ssh_key_file)
        }
    }
    provisioner "file" {
        content = <<-EOF

            if [ "${length( regexall("lead", join(",", self.tags)) ) > 0}" = "true" ]; then
               docker node update --availability="drain" ${self.name}
               sleep 20;
               docker node demote ${self.name}
               sleep 5
               docker swarm leave
               docker swarm leave --force;
               exit 0
           fi
        EOF
        destination = "/tmp/remove.sh"
        connection {
            host     = self.ipv4_address
            type     = "ssh"
            user     = "root"
            private_key = file(var.config.local_ssh_key_file)
        }
    }


    provisioner "local-exec" {
        when = destroy
        command = <<-EOF
            ssh-keygen -R ${self.ipv4_address}
            exit 0;
        EOF
        on_failure = continue
    }


    provisioner "remote-exec" {
        when = destroy
        inline = [
            <<-EOF
                consul leave;
                if [ "${length( regexall("build", join(",", self.tags)) ) > 0}" = "true" ]; then
                    chmod +x /home/gitlab-runner/rmscripts/rmrunners.sh;
                    bash /home/gitlab-runner/rmscripts/rmrunners.sh;
                fi
            EOF
        ]
        on_failure = continue
        connection {
            host     = self.ipv4_address
            type     = "ssh"
            user     = "root"
        }
    }
}

resource "null_resource" "cleanup_consul" {
    count = 1
    depends_on = [ digitalocean_droplet.main ]

    triggers = {
        machine_ids = join(",", digitalocean_droplet.main[*].id)
    }

    provisioner "file" {
        content = <<-EOF
            #Wait for consul to detect failure;
            sleep 20;
            DOWN_MEMBERS=( $(consul members | grep "left\|failed" | cut -d " " -f1) )
            echo "DOWN MEMBERS: $${DOWN_MEMBERS[@]}"
            if [ -n "$DOWN_MEMBERS" ]; then
                for MEMBER in "$${DOWN_MEMBERS[@]}"
                do
                    echo "Force leaving: $MEMBER";
                    consul force-leave $MEMBER;
                done
            fi
            exit 0;
        EOF
        destination = "/tmp/update_consul_members.sh"
    }
    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/update_consul_members.sh",
            "bash /tmp/update_consul_members.sh"
        ]
    }

    connection {
        host = element(digitalocean_droplet.main[*].ipv4_address, 0)
        type = "ssh"
    }
}



resource "null_resource" "cleanup" {
    count = 1

    triggers = {
        should_downsize = var.config.downsize
    }

    #### all proxies admin   -> change nginx route ip -> safe to leave swarm
    #### dockerconstraint.sh -> changeip-NAME.sh      -> remove.sh
    #### Once docker app proxying happens on nginx instead of docker proxy app, this will be revisted

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/dockerconstraint.sh",
            var.config.downsize ? "/tmp/dockerconstraint.sh" : "echo 0",
        ]
        connection {
            host     = element(digitalocean_droplet.main[*].ipv4_address, length(digitalocean_droplet.main[*].ipv4_address) - 1 )
            type     = "ssh"
            user     = "root"
            private_key = file(var.config.local_ssh_key_file)
        }
    }
    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/changeip-${element(digitalocean_droplet.main[*].name, length(digitalocean_droplet.main[*].name) - 1)}.sh",
            var.config.downsize ? "/tmp/changeip-${element(digitalocean_droplet.main[*].name, length(digitalocean_droplet.main[*].name) - 1)}.sh" : "echo 0",
        ]
        connection {
            host     = element(digitalocean_droplet.main[*].ipv4_address, 0)
            type     = "ssh"
            user     = "root"
            private_key = file(var.config.local_ssh_key_file)
        }
    }
    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/remove.sh",
            var.config.downsize ? "/tmp/remove.sh" : "echo 0",
        ]
        connection {
            host     = element(digitalocean_droplet.main[*].ipv4_address, length(digitalocean_droplet.main[*].ipv4_address) - 1 )
            type     = "ssh"
            user     = "root"
            private_key = file(var.config.local_ssh_key_file)
        }
    }
}
