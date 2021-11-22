##NOTE: image_size is packer snapshot size, not instance size

module "admin" {
    source = "./droplets"
    ##TODO: Limit to 1 atm
    for_each = {
        for ind, cfg in local.admin_cfg_servers:
        cfg.key => { cfg = cfg, ind = ind }
    }
    servers = each.value.cfg.server

    config = var.config
    image_name = local.do_image_name
    image_size = "s-2vcpu-4gb"
    tags = local.do_tags
    vpc_uuid = digitalocean_vpc.terraform_vpc.id
}
module "lead" {
    source = "./droplets"
    for_each = {
        for ind, cfg in local.lead_cfg_servers:
        cfg.key => { cfg = cfg, ind = ind }
    }
    servers = each.value.cfg.server

    config = var.config
    image_name = local.do_image_small_name
    image_size = "s-1vcpu-1gb"
    tags = local.do_small_tags
    vpc_uuid = digitalocean_vpc.terraform_vpc.id

    admin_ip_public = local.admin_servers > 0 ? data.digitalocean_droplets.admin.droplets[0].ipv4_address : ""
    consul_lan_leader_ip = (local.admin_servers > 0
        ? data.digitalocean_droplets.admin.droplets[0].ipv4_address_private
        : (each.value.ind == 0 ? "" : data.digitalocean_droplets.lead.droplets[0].ipv4_address_private)
    )
}
module "db" {
    source = "./droplets"
    ##TODO: Limit to 1 atm
    for_each = {
        for ind, cfg in local.db_cfg_servers:
        cfg.key => { cfg = cfg, ind = ind }
    }
    servers = each.value.cfg.server

    config = var.config
    image_name = local.do_image_small_name
    image_size = "s-1vcpu-1gb"
    tags = local.do_small_tags
    vpc_uuid = digitalocean_vpc.terraform_vpc.id

    admin_ip_public = local.admin_servers > 0 ? data.digitalocean_droplets.admin.droplets[0].ipv4_address : ""
    consul_lan_leader_ip = local.admin_servers > 0 ? data.digitalocean_droplets.admin.droplets[0].ipv4_address_private : data.digitalocean_droplets.lead.droplets[0].ipv4_address_private
}
module "build" {
    source = "./droplets"
    for_each = {
        for ind, cfg in local.build_cfg_servers:
        cfg.key => { cfg = cfg, ind = ind }
    }
    servers = each.value.cfg.server

    config = var.config
    image_name = local.do_image_small_name
    image_size = "s-1vcpu-1gb"
    tags = local.do_small_tags
    vpc_uuid = digitalocean_vpc.terraform_vpc.id

    admin_ip_public = local.admin_servers > 0 ? data.digitalocean_droplets.admin.droplets[0].ipv4_address : ""
    consul_lan_leader_ip = local.admin_servers > 0 ? data.digitalocean_droplets.admin.droplets[0].ipv4_address_private : data.digitalocean_droplets.lead.droplets[0].ipv4_address_private
}

### TODO: According to
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/instances
### Its better to use terraform_remote_state data source, will need to investigate
# https://www.terraform.io/docs/language/state/remote-state-data.html

##NOTE: Reason not using data resource for ips anymore, using the data resource reads before destroy
##  so its unaware which IP will be gone and causes an outage if replacing the first/older machine
data "digitalocean_droplets" "admin" {
    depends_on = [
        module.admin.id,
    ]
    filter {
        key    = "name"
        values = [ "${var.config.server_name_prefix}-${var.config.region}" ]
        match_by = "re"
    }
    filter {
        key    = "tags"
        values = [ "admin" ]
        all = true
    }
    sort {
        key       = "created_at"
        direction = "asc"
    }
    sort {
        key       = "size"
        direction = "desc"
    }
}
data "digitalocean_droplets" "lead" {
    depends_on = [
        module.admin.id,
        module.lead.id,
    ]
    filter {
        key    = "name"
        values = [ "${var.config.server_name_prefix}-${var.config.region}" ]
        match_by = "re"
    }
    filter {
        key    = "tags"
        values = [ "lead" ]
        all = true
    }
    sort {
        key       = "created_at"
        direction = "asc"
    }
    sort {
        key       = "size"
        direction = "desc"
    }
}
data "digitalocean_droplets" "db" {
    depends_on = [
        module.admin.id,
        module.db.id,
    ]
    filter {
        key    = "name"
        values = [ "${var.config.server_name_prefix}-${var.config.region}" ]
        match_by = "re"
    }
    filter {
        key    = "tags"
        values = [ "db" ]
        all = true
    }
    sort {
        key       = "created_at"
        direction = "asc"
    }
    sort {
        key       = "size"
        direction = "desc"
    }
}
data "digitalocean_droplets" "build" {
    depends_on = [
        module.admin.id,
        module.build.id
    ]
    filter {
        key    = "name"
        values = [ "${var.config.server_name_prefix}-${var.config.region}" ]
        match_by = "re"
    }
    filter {
        key    = "tags"
        values = [ "build" ]
        all = true
    }
    sort {
        key       = "created_at"
        direction = "asc"
    }
    sort {
        key       = "size"
        direction = "desc"
    }
}

##TODO: Ansible playbook to run at end like kubernetes/docker or in mod.consul itself
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
            sleep 300;
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
        host = element(concat(local.admin_public_ips, local.lead_public_ips), 0)
        type = "ssh"
    }
}
