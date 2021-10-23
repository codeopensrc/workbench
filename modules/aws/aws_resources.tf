data "aws_ami_ids" "latest" {
    owners = ["self"]

    filter {
        name   = "tag:Type"
        values = [ "build" ]
    }
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
    ## TODO: Dynamically look for this tag on refactor
    filter {
        name   = "tag:gitlab_version"
        values = [ var.config.packer_config.gitlab_version ]
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
    source             = "../packer"
    build = length(data.aws_ami_ids.latest.ids) >= 1 ? false : true

    active_env_provider = var.config.active_env_provider

    aws_access_key = var.config.aws_access_key
    aws_secret_key = var.config.aws_secret_key
    aws_region = var.config.aws_region
    aws_key_name = var.config.aws_key_name
    aws_instance_type = "t2.medium"

    do_token = var.config.do_token
    digitalocean_region = var.config.do_region
    digitalocean_image_size = "s-2vcpu-4gb"
    digitalocean_image_name = ""

    packer_config = var.config.packer_config
}

data "aws_ami" "new" {
    depends_on = [ module.packer ]
    most_recent = true

    owners = ["self"]

    filter {
        name   = "tag:Type"
        values = [ "build" ]
    }
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
    ## TODO: Dynamically look for this tag on refactor
    filter {
        name   = "tag:gitlab_version"
        values = [ var.config.packer_config.gitlab_version ]
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

resource "aws_instance" "main" {
    # TODO: total of all counts
    count = length(var.config.servers)
    depends_on = [aws_internet_gateway.igw]
    key_name = var.config.aws_key_name
    #Priorty = Provided image id -> Latest image with matching filters -> Build if no matches
    ami = (var.config.servers[count.index].image != ""
        ? var.config.servers[count.index].image
        : (length(data.aws_ami_ids.latest.ids) > 0 ? data.aws_ami_ids.latest.ids[0] : data.aws_ami.new.id)
    )
    instance_type = var.config.servers[count.index].size["aws"]

    tags = {
        Name = "${var.config.server_name_prefix}-${var.config.region}-${local.server_names[count.index]}-${substr(uuid(), 0, 4)}"
        Roles = join(",", var.config.servers[count.index].roles)
    }
    #"TODO: Tag admin with gitlab.${var.config.root_domain_name}"
    lifecycle {
        ignore_changes= [ tags ]
    }

    root_block_device {
        volume_size = var.config.servers[count.index].aws_volume_size
    }

    subnet_id              = aws_subnet.public_subnet.id

    vpc_security_group_ids = compact([
        aws_security_group.default_ports.id,
        aws_security_group.ext_remote.id,

        contains(var.config.servers[count.index].roles, "admin") ? aws_security_group.admin_ports.id : "",
        contains(var.config.servers[count.index].roles, "lead") ? aws_security_group.app_ports.id : "",

        contains(var.config.servers[count.index].roles, "db") ? aws_security_group.db_ports.id : "",
        contains(var.config.servers[count.index].roles, "db") ? aws_security_group.ext_db.id : "",
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

            IS_LEAD=${contains(var.config.servers[count.index].roles, "lead") ? "true" : ""}

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

            IS_LEAD=${contains(var.config.servers[count.index].roles, "lead") ? "true" : ""}

            if [ "$IS_LEAD" = "true" ]; then
                sed -i "s|${self.private_ip}|${aws_instance.main[0].private_ip}|" /etc/nginx/conf.d/proxy.conf
                gitlab-ctl reconfigure
            fi

        EOF
        destination = "/tmp/changeip-${self.tags.Name}.sh"
        connection {
            host     = aws_instance.main[0].public_ip
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

    provisioner "local-exec" {
        when = destroy
        command = <<-EOF
            ssh-keygen -R ${self.public_ip};
            WORKSPACE="unknown";
            ## TODO-Tag admin with var.config.root_domain_name

            if [ "$WORKSPACE" != "default" ]; then
                ## TODO: Create parsable domain from tag
                ## "${length( regexall("domain", join(",", self.tags)) ) > 0}"
                ## ssh-keygen -R "gitlab."
                echo "Not default"
            fi
            exit 0;
        EOF
        on_failure = continue
    }
}

resource "null_resource" "cleanup_consul" {
    count = 1
    depends_on = [ aws_instance.main ]

    triggers = {
        machine_ids = join(",", aws_instance.main[*].id)
    }

    provisioner "file" {
        content = <<-EOF
            #Wait for consul to detect failure;
            sleep 120;
            DOWN_MEMBERS=( $(consul members | grep "left\|failed" | cut -d " " -f1) )
            echo "DOWN MEMBERS: $${DOWN_MEMBERS[@]}"
            if [ -n "$DOWN_MEMBERS" ]; then
                for MEMBER in "$${DOWN_MEMBERS[@]}"
                do
                    echo "Force leaving: $MEMBER";
                    consul force-leave -prune $MEMBER;
                done
            fi
            exit 0;
        EOF
        destination = "/tmp/update_consul_members.sh"
    }
    ##! Uses tmux to run in the background and let remaining scripts run to remove nodes
    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/update_consul_members.sh",
            "tmux new -d -s update_consul",
            "tmux send -t update_consul.0 \"bash /tmp/update_consul_members.sh; exit\" ENTER"
        ]
    }

    connection {
        host = element(aws_instance.main[*].public_ip, 0)
        type = "ssh"
    }
}

###! TODO: Update to use kubernetes instead of docker swarm
###! Run this resource when downsizing from 2 leader servers to 1 in its own apply
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
            host     = element(aws_instance.main[*].public_ip, length(aws_instance.main[*].public_ip) - 1 )
            type     = "ssh"
            user     = "root"
            private_key = file(var.config.local_ssh_key_file)
        }
    }
    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/changeip-${element(aws_instance.main[*].tags.Name, length(aws_instance.main[*].tags.Name) - 1)}.sh",
            var.config.downsize ? "/tmp/changeip-${element(aws_instance.main[*].tags.Name, length(aws_instance.main[*].tags.Name) - 1)}.sh" : "echo 0",
        ]
        connection {
            host     = element(aws_instance.main[*].public_ip, 0)
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
            host     = element(aws_instance.main[*].public_ip, length(aws_instance.main[*].public_ip) - 1 )
            type     = "ssh"
            user     = "root"
            private_key = file(var.config.local_ssh_key_file)
        }
    }
}

### Some sizes for reference
# variable "aws_admin_instance_type" { default = "t3a.large" }
# variable "aws_leader_instance_type" { default = "t3a.small" }
# variable "aws_db_instance_type" { default = "t3a.micro" }
