
data "aws_ami_ids" "latest" {
    owners = ["self"]

    filter {
        name   = "tag:consul_version"
        values = [ var.config.packer_config.consul_version ]
    }
    filter {
        name   = "tag:docker_version"
        values = [ var.config.packer_config.docker_version ]
    }
    filter {
        name   = "tag:docker_compose_version"
        values = [ var.config.packer_config.docker_compose_version ]
    }
    filter {
        name   = "tag:gitlab_version"
        values = [ var.servers.roles[0] == "admin" ? var.config.packer_config.gitlab_version : "" ]
    }
    filter {
        name   = "tag:redis_version"
        values = [ var.config.packer_config.redis_version ]
    }
    filter {
        name   = "tag:aws_key_name"
        values = [ var.config.aws_key_name ]
    }
}

module "packer" {
    source             = "../../packer"
    build = length(data.aws_ami_ids.latest.ids) >= 1 ? false : true

    active_env_provider = var.config.active_env_provider
    role = var.servers.roles[0]

    aws_access_key = var.config.aws_access_key
    aws_secret_key = var.config.aws_secret_key
    aws_region = var.config.aws_region
    aws_key_name = var.config.aws_key_name
    aws_instance_type = var.image_size

    do_token = var.config.do_token
    digitalocean_region = var.config.do_region
    digitalocean_image_size = ""
    digitalocean_image_name = ""

    packer_config = var.config.packer_config
}

data "aws_ami" "new" {
    depends_on = [ module.packer ]
    most_recent = true

    owners = ["self"]

    filter {
        name   = "tag:consul_version"
        values = [ var.config.packer_config.consul_version ]
    }
    filter {
        name   = "tag:docker_version"
        values = [ var.config.packer_config.docker_version ]
    }
    filter {
        name   = "tag:docker_compose_version"
        values = [ var.config.packer_config.docker_compose_version ]
    }
    filter {
        name   = "tag:gitlab_version"
        values = [ var.servers.roles[0] == "admin" ? var.config.packer_config.gitlab_version : "" ]
    }
    filter {
        name   = "tag:redis_version"
        values = [ var.config.packer_config.redis_version ]
    }
    filter {
        name   = "tag:aws_key_name"
        values = [ var.config.aws_key_name ]
    }
}

resource "random_uuid" "server" {}

## We use to indirectly depend on vpc which is necesssary to destroy aws_instance
resource "null_resource" "vpc_dependencies" {
    triggers = {
        subnet_id = var.vpc.aws_subnet.public_subnet.id
        aws_route_table_association_id = var.vpc.aws_route_table_association.public_subnet_assoc.id
        aws_route_table_id = var.vpc.aws_route_table.rtb.id
        aws_route_id = var.vpc.aws_route.internet_access.id
        igw_id = var.vpc.aws_internet_gateway.igw.id
        default_ports_id = var.vpc.aws_security_group.default_ports.id
    }
}

resource "aws_instance" "main" {
    ## Depend on vpc in order to be able to connect on destroy
    #https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway
    depends_on = [null_resource.vpc_dependencies]

    key_name = var.config.aws_key_name
    #Priorty = Provided image id -> Latest image with matching filters -> Build if no matches
    ami = (var.servers.image != ""
        ? var.servers.image
        : (length(data.aws_ami_ids.latest.ids) > 0 ? data.aws_ami_ids.latest.ids[0] : data.aws_ami.new.id)
    )
    instance_type = var.servers.size["aws"]

    tags = {
        Name = "${var.config.server_name_prefix}-${var.config.region}-${var.servers.roles[0]}-${substr(random_uuid.server.id, 0, 4)}",
        Domain = contains(var.servers.roles, "admin") ? "gitlab-${replace(var.config.root_domain_name, ".", "-")}" : "",
        Roles = join(",", var.servers.roles)
        Prefix = "${var.config.server_name_prefix}-${var.config.region}"
        Admin = contains(var.servers.roles, "admin") ? true : false
        DB = contains(var.servers.roles, "db") ? true : false
        Lead = contains(var.servers.roles, "lead") ? true : false
        Build = contains(var.servers.roles, "build") ? true : false
    }
    lifecycle {
        ignore_changes= [ tags ]
    }

    root_block_device {
        volume_size = var.servers.aws_volume_size
    }

    subnet_id              = var.vpc.aws_subnet.public_subnet.id

    vpc_security_group_ids = compact([
        var.vpc.aws_security_group.default_ports.id,
        var.vpc.aws_security_group.ext_remote.id,

        contains(var.servers.roles, "admin") ? var.vpc.aws_security_group.admin_ports.id : "",
        contains(var.servers.roles, "lead") ? var.vpc.aws_security_group.app_ports.id : "",

        contains(var.servers.roles, "db") ? var.vpc.aws_security_group.db_ports.id : "",
        contains(var.servers.roles, "db") ? var.vpc.aws_security_group.ext_db.id : "",
    ])

    provisioner "remote-exec" {
        inline = [ "cat /home/ubuntu/.ssh/authorized_keys | sudo tee /root/.ssh/authorized_keys" ]
        connection {
            host     = self.public_ip
            type     = "ssh"
            user     = "ubuntu"
            private_key = file(var.config.local_ssh_key_file)
        }
    }

    ###! TODO: Update to use kubernetes instead of docker swarm
    ## Runs when `var.config.downsize` is true
    provisioner "file" {
        content = <<-EOF

            IS_LEAD=${contains(var.servers.roles, "lead") ? "true" : ""}

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
            private_key = file(var.config.local_ssh_key_file)
        }
    }
    ## Runs when `var.config.downsize` is true
    provisioner "file" {
        content = <<-EOF
            IS_LEAD=${var.servers.roles[0] == "lead" ? "true" : ""}
            ADMIN_IP=${var.admin_ip_private}

            if [ "$IS_LEAD" = "true" ]; then
                sed -i "s|${self.private_ip}|${var.admin_ip_private}|" /etc/nginx/conf.d/proxy.conf
                gitlab-ctl reconfigure
            fi

        EOF
        destination = "/tmp/changeip-${self.tags.Name}.sh"
        connection {
            host     = var.admin_ip_public != "" ? var.admin_ip_public : self.public_ip
            type     = "ssh"
            user     = "root"
            private_key = file(var.config.local_ssh_key_file)
        }
    }
    ###! TODO: Update to use kubernetes instead of docker swarm
    ## Runs when `var.config.downsize` is true
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
            private_key = file(var.config.local_ssh_key_file)
        }
    }

    provisioner "remote-exec" {
        when = destroy
        inline = [
            <<-EOF
                consul leave;
                if [ "${length( regexall("build", self.tags.Roles) ) > 0}" = "true" ]; then
                    chmod +x /home/gitlab-runner/rmscripts/rmrunners.sh;
                    bash /home/gitlab-runner/rmscripts/rmrunners.sh;
                fi
            EOF
        ]
        on_failure = continue
        connection {
            host     = self.public_ip
            type     = "ssh"
            user     = "root"
        }
    }

    ## TODO: Confirm this works for aws .tags.Roles correctly
    provisioner "local-exec" {
        when = destroy
        command = <<-EOF
            ssh-keygen -R ${self.public_ip};

            if [ "${terraform.workspace}" != "default" ]; then
                ${self.tags.Domain != "" ? "ssh-keygen -R \"${replace(regex("gitlab-[a-z]+-[a-z]+", self.tags.Domain), "-", ".")}\"" : ""}
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

    public_ip = aws_instance.main.public_ip
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
    consul_lan_leader_ip = var.consul_lan_leader_ip != "" ? var.consul_lan_leader_ip : aws_instance.main.private_ip
    #consul_wan_leader_ip = var.consul_wan_leader_ip

    name = aws_instance.main.tags.Name
    public_ip = aws_instance.main.public_ip
    private_ip = aws_instance.main.private_ip
}

module "hostname" {
    source = "../../hostname"
    depends_on = [module.init, module.consul]

    region = var.config.region
    server_name_prefix = var.config.server_name_prefix
    root_domain_name = var.config.root_domain_name
    hostname = "${var.config.gitlab_subdomain}.${var.config.root_domain_name}"

    name = aws_instance.main.tags.Name
    public_ip = aws_instance.main.public_ip
    private_ip = aws_instance.main.private_ip
}

module "cron" {
    source = "../../cron"
    depends_on = [module.init, module.consul, module.hostname]

    public_ip = aws_instance.main.public_ip
    roles = var.servers.roles
    s3alias = var.config.s3alias
    s3bucket = var.config.s3bucket
    use_gpg = var.config.use_gpg

    # Leader specific
    app_definitions = var.config.app_definitions

    # Admin specific
    gitlab_backups_enabled = var.config.gitlab_backups_enabled

    # DB specific
    redis_dbs = var.config.redis_dbs
    mongo_dbs = var.config.mongo_dbs
    pg_dbs = var.config.pg_dbs
}

module "provision" {
    source = "../../provision"
    depends_on = [module.init, module.consul, module.hostname, module.cron]

    public_ip = aws_instance.main.public_ip

    known_hosts = var.config.known_hosts
    root_domain_name = var.config.root_domain_name
    deploy_key_location = var.config.deploy_key_location

    # DB checks
    pg_read_only_pw = var.config.pg_read_only_pw
    private_ip = aws_instance.main.private_ip
}
