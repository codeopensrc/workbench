
resource "digitalocean_droplet" "main" {
    count = var.active_env_provider == "digital_ocean" ? length(var.servers) : 0
    name     = "${var.server_name_prefix}-${var.region}-${local.server_names[count.index]}-${substr(uuid(), 0, 4)}"
    image    = var.servers[count.index].image == "" ? var.packer_image_id : var.servers[count.index].image
    region   = var.region
    size     = var.servers[count.index].size["digital_ocean"]
    ssh_keys = [var.do_ssh_fingerprint]
    tags = flatten([
        "${var.server_name_prefix}-${var.region}-${local.server_names[count.index]}-${substr(uuid(), 0, 4)}",
        var.servers[count.index].roles
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
            private_key = file(var.local_ssh_key_file)
        }
    }

    provisioner "file" {
        content = <<-EOF

            IS_LEAD=${contains(var.servers[count.index].roles, "lead") ? "true" : ""}

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
            private_key = file(var.local_ssh_key_file)
        }
    }
    provisioner "file" {
        content = <<-EOF

            IS_LEAD=${contains(var.servers[count.index].roles, "lead") ? "true" : ""}

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
            private_key = file(var.local_ssh_key_file)
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
            private_key = file(var.local_ssh_key_file)
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


}


resource "null_resource" "cleanup" {
    count = var.active_env_provider == "digital_ocean" ? 1 : 0

    triggers = {
        should_downsize = var.downsize
    }

    #### all proxies admin   -> change nginx route ip -> safe to leave swarm
    #### dockerconstraint.sh -> changeip-NAME.sh      -> remove.sh
    #### Once docker app proxying happens on nginx instead of docker proxy app, this will be revisted

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/dockerconstraint.sh",
            var.downsize ? "/tmp/dockerconstraint.sh" : "echo 0",
        ]
        connection {
            host     = element(digitalocean_droplet.main[*].ipv4_address, length(digitalocean_droplet.main[*].ipv4_address) - 1 )
            type     = "ssh"
            user     = "root"
            private_key = file(var.local_ssh_key_file)
        }
    }
    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/changeip-${element(digitalocean_droplet.main[*].name, length(digitalocean_droplet.main[*].name) - 1)}.sh",
            var.downsize ? "/tmp/changeip-${element(digitalocean_droplet.main[*].name, length(digitalocean_droplet.main[*].name) - 1)}.sh" : "echo 0",
        ]
        connection {
            host     = element(digitalocean_droplet.main[*].ipv4_address, 0)
            type     = "ssh"
            user     = "root"
            private_key = file(var.local_ssh_key_file)
        }
    }
    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/remove.sh",
            var.downsize ? "/tmp/remove.sh" : "echo 0",
        ]
        connection {
            host     = element(digitalocean_droplet.main[*].ipv4_address, length(digitalocean_droplet.main[*].ipv4_address) - 1 )
            type     = "ssh"
            user     = "root"
            private_key = file(var.local_ssh_key_file)
        }
    }
}
