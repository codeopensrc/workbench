## Cannot filter DROPLET snapshots by tags as they cannot be tagged (currently apparently)
## https://docs.digitalocean.com/reference/api/api-reference/#tag/Tags
data "digitalocean_images" "latest" {
    filter {
        key    = "name"
        values = [ var.image_name ]
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
    source             = "../../packer"
    build = length(data.digitalocean_images.latest.images) >= 1 ? false : true

    active_env_provider = var.config.active_env_provider

    aws_access_key = var.config.aws_access_key
    aws_secret_key = var.config.aws_secret_key
    aws_region = var.config.aws_region
    aws_key_name = var.config.aws_key_name
    aws_instance_type = "t2.medium" #var.instance_type

    do_token = var.config.do_token
    digitalocean_region = var.config.do_region
    digitalocean_image_size = var.image_size
    digitalocean_image_name = var.image_name

    packer_config = var.config.packer_config
}

data "digitalocean_images" "new" {
    depends_on = [ module.packer ]
    filter {
        key    = "name"
        values = [ var.image_name ]
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

resource "random_uuid" "server" { count = var.servers.count }

resource "digitalocean_droplet" "main" {
    count = var.servers.count
    name     = "${var.config.server_name_prefix}-${var.config.region}-${var.servers.roles[0]}-${substr(random_uuid.server[count.index].id, 0, 4)}"
    #Priorty = Provided image id -> Latest image with matching filters -> Build if no matches
    image = (var.servers.image != ""
        ? var.servers.image
        : (length(data.digitalocean_images.latest.images) > 0
            ? data.digitalocean_images.latest.images[0].id : data.digitalocean_images.new.images[0].id)
    )
    region   = var.config.region
    size     = var.servers.size["digital_ocean"]
    ssh_keys = [var.config.do_ssh_fingerprint]
    tags = compact(flatten([
        "${var.config.server_name_prefix}-${var.config.region}-${var.servers.roles[0]}-${substr(random_uuid.server[count.index].id, 0, 4)}",
        contains(var.servers.roles, "admin") ? "gitlab-${replace(var.config.root_domain_name, ".", "-")}" : "",
        var.servers.roles,
        var.tags
    ]))

    lifecycle {
        ignore_changes = [name, tags]
    }

    vpc_uuid = var.vpc_uuid


    provisioner "remote-exec" {
        inline = [ "cat /home/ubuntu/.ssh/authorized_keys | sudo tee /root/.ssh/authorized_keys" ]
        connection {
            host     = self.ipv4_address
            type     = "ssh"
            user     = "root"
            private_key = file(var.config.local_ssh_key_file)
        }
    }

    ###! TODO: Update to use kubernetes instead of docker swarm
    ## Runs when `var.config.downsize` is true
    provisioner "file" {
        content = <<-EOF

            IS_LEAD=${contains(var.servers.roles, "lead") ? "true" : ""}

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
    ## Runs when `var.config.downsize` is true
    provisioner "file" {
        content = <<-EOF
            IS_LEAD=${var.servers.roles[0] == "lead" ? "true" : ""}
            ADMIN_IP=${var.admin_ip_private}

            if [ "$IS_LEAD" = "true" && -n "$ADMIN_IP" ]; then
                sed -i "s|${self.ipv4_address_private}|${var.admin_ip_private}|" /etc/nginx/conf.d/proxy.conf
                gitlab-ctl reconfigure
            fi

        EOF
        destination = "/tmp/changeip-${self.name}.sh"
        connection {
            host     = var.admin_ip_public != "" ? var.admin_ip_public : self.ipv4_address
            type     = "ssh"
            user     = "root"
            private_key = file(var.config.local_ssh_key_file)
        }
    }
    ###! TODO: Update to use kubernetes instead of docker swarm
    ## Runs when `var.config.downsize` is true
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

    provisioner "local-exec" {
        when = destroy
        command = <<-EOF
            ssh-keygen -R ${self.ipv4_address};

            if [ "${terraform.workspace}" != "default" ]; then
                ${contains(self.tags, "admin") ? "ssh-keygen -R \"${replace(regex("gitlab-[a-z]+-[a-z]+", join(",", self.tags)), "-", ".")}\"" : ""}
                echo "Not default"
            fi
            exit 0;
        EOF
        on_failure = continue
    }
}

