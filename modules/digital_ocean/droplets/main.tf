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
    role = var.servers.roles[0]

    aws_access_key = var.config.aws_access_key
    aws_secret_key = var.config.aws_secret_key
    aws_region = var.config.aws_region
    aws_key_name = var.config.aws_key_name
    aws_instance_type = ""

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

resource "random_uuid" "server" {}

resource "digitalocean_droplet" "main" {
    name     = "${var.config.server_name_prefix}-${var.config.region}-${var.servers.roles[0]}-${substr(random_uuid.server.id, 0, 4)}"
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
        "${var.config.server_name_prefix}-${var.config.region}-${var.servers.roles[0]}-${substr(random_uuid.server.id, 0, 4)}",
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

### TODO: Most or all of the modules will not have a count attribute
## once we scale machines one level higher at the module level

module "init" {
    source = "../../init"

    public_ip = digitalocean_droplet.main.ipv4_address
    do_spaces_region = var.config.do_spaces_region
    do_spaces_access_key = var.config.do_spaces_access_key
    do_spaces_secret_key = var.config.do_spaces_secret_key

    aws_bot_access_key = var.config.aws_bot_access_key
    aws_bot_secret_key = var.config.aws_bot_secret_key
}

module "consul" {
    source = "../../consul"
    depends_on = [module.init]

    role = var.servers.roles[0]
    region = var.config.region
    datacenter_has_admin = var.admin_ip_public != "" ? true : false
    consul_lan_leader_ip = var.consul_lan_leader_ip != "" ? var.consul_lan_leader_ip : digitalocean_droplet.main.ipv4_address_private
    #consul_wan_leader_ip = var.consul_wan_leader_ip

    name = digitalocean_droplet.main.name
    public_ip = digitalocean_droplet.main.ipv4_address
    private_ip = digitalocean_droplet.main.ipv4_address_private
}

module "hostname" {
    source = "../../hostname"
    depends_on = [module.init, module.consul]

    region = var.config.region
    server_name_prefix = var.config.server_name_prefix
    root_domain_name = var.config.root_domain_name
    hostname = "${var.config.gitlab_subdomain}.${var.config.root_domain_name}"

    name = digitalocean_droplet.main.name
    public_ip = digitalocean_droplet.main.ipv4_address
    private_ip = digitalocean_droplet.main.ipv4_address_private
}

module "cron" {
    source = "../../cron"
    depends_on = [module.init, module.consul, module.hostname]

    public_ip = digitalocean_droplet.main.ipv4_address
    roles = var.servers.roles
    s3alias = var.config.s3alias
    s3bucket = var.config.s3bucket
    use_gpg = var.config.use_gpg

    # Leader specific
    app_definitions = var.config.app_definitions

    # Admin specific
    gitlab_backups_enabled = var.config.gitlab_backups_enabled

    # DB specific
    redis_dbs = length(var.config.redis_dbs) > 0 ? var.config.redis_dbs : []
    mongo_dbs = length(var.config.mongo_dbs) > 0 ? var.config.mongo_dbs : []
    pg_dbs = length(var.config.pg_dbs) > 0 ? var.config.pg_dbs : []
}

module "provision" {
    source = "../../provision"
    depends_on = [module.init, module.consul, module.hostname, module.cron]

    public_ip = digitalocean_droplet.main.ipv4_address

    known_hosts = var.config.known_hosts
    root_domain_name = var.config.root_domain_name
    deploy_key_location = var.config.deploy_key_location

    # DB checks
    pg_read_only_pw = var.config.pg_read_only_pw
    private_ip = digitalocean_droplet.main.ipv4_address_private
}
