module "admin" {
    source = "./droplets"
    count = local.admin_servers > 0 ? 1 : 0

    servers = local.admin_cfg_servers[0]
    config = var.config
    image_name = local.do_image_name
    image_size = "s-2vcpu-4gb"
    tags = local.do_tags
    vpc_uuid = digitalocean_vpc.terraform_vpc.id
}
module "lead" {
    source = "./droplets"
    count = local.is_only_leader_count > 0 ? 1 : 0

    servers = local.lead_cfg_servers[0]
    config = var.config
    image_name = local.do_image_small_name
    image_size = "s-1vcpu-1gb"
    tags = local.do_small_tags
    vpc_uuid = digitalocean_vpc.terraform_vpc.id

    admin_ip_public = local.admin_servers > 0 ? element(local.admin_public_ips, 0) : ""
    admin_ip_private = local.admin_servers > 0 ? element(local.admin_private_ips, 0) : ""
}
module "db" {
    source = "./droplets"
    count = local.is_only_db_count > 0 ? 1 : 0

    servers = local.db_cfg_servers[0]
    config = var.config
    image_name = local.do_image_small_name
    image_size = "s-1vcpu-1gb"
    tags = local.do_small_tags
    vpc_uuid = digitalocean_vpc.terraform_vpc.id

    admin_ip_public = local.admin_servers > 0 ? element(local.admin_public_ips, 0) : ""
    admin_ip_private = local.admin_servers > 0 ? element(local.admin_private_ips, 0) : ""
    consul_lan_leader_ip = element(concat(local.admin_private_ips, local.lead_private_ips), 0)
}
module "build" {
    source = "./droplets"
    count = local.is_only_build_count > 0 ? 1 : 0

    servers = local.build_cfg_servers[0]
    config = var.config
    image_name = local.do_image_small_name
    image_size = "s-1vcpu-1gb"
    tags = local.do_small_tags
    vpc_uuid = digitalocean_vpc.terraform_vpc.id

    admin_ip_public = local.admin_servers > 0 ? element(local.admin_public_ips, 0) : ""
    admin_ip_private = local.admin_servers > 0 ? element(local.admin_private_ips, 0) : ""
    consul_lan_leader_ip = element(concat(local.admin_private_ips, local.lead_private_ips), 0)
}


resource "null_resource" "cleanup_consul" {
    count = 1
    depends_on = [
        module.admin,
        module.lead,
        module.db,
        module.build,
    ]

    triggers = {
        machine_ids = join(",", local.all_server_ids)
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
        host = element(local.all_public_ips, 0)
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
            host = element(local.lead_public_ips, length(local.lead_public_ips) - 1)
            type     = "ssh"
            user     = "root"
            private_key = file(var.config.local_ssh_key_file)
        }
    }
    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/changeip-${element(local.lead_names, length(local.lead_names) - 1)}.sh",
            var.config.downsize ? "/tmp/changeip-${element(local.lead_names, length(local.lead_names) - 1)}.sh" : "echo 0",
        ]
        connection {
            host = element(local.all_public_ips, 0)
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
            host = element(local.lead_public_ips, length(local.lead_public_ips) - 1)
            type     = "ssh"
            user     = "root"
            private_key = file(var.config.local_ssh_key_file)
        }
    }
}
