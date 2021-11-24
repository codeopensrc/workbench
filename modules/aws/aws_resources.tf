##NOTE: image_size is packer ami size, not instance size
### Some sizes for reference
#t3a.large  = 2vcpu 8gbMem
#t3a.medium = 2vcpu 4gbMem
#t3a.small  = 2vcpu 2gbMem
#t3a.micro  = 2vcpu 1gbMem 
#t3a.nano   = 2vcpu .5gbMem 

module "admin" {
    source = "./instances"
    ##TODO: Limit to 1 atm
    for_each = {
        for ind, cfg in local.admin_cfg_servers:
        cfg.key => { cfg = cfg, ind = ind }
    }
    servers = each.value.cfg.server

    config = var.config
    image_size = "t3a.medium"
    vpc = local.vpc
}
module "lead" {
    source = "./instances"
    for_each = {
        for ind, cfg in local.lead_cfg_servers:
        cfg.key => { cfg = cfg, ind = ind }
    }
    servers = each.value.cfg.server

    config = var.config
    image_size = "t3a.micro"
    vpc = local.vpc
}
module "db" {
    source = "./instances"
    ##TODO: Limit to 1 atm
    for_each = {
        for ind, cfg in local.db_cfg_servers:
        cfg.key => { cfg = cfg, ind = ind }
    }
    servers = each.value.cfg.server

    config = var.config
    image_size = "t3a.micro"
    vpc = local.vpc
}
module "build" {
    source = "./instances"
    for_each = {
        for ind, cfg in local.build_cfg_servers:
        cfg.key => { cfg = cfg, ind = ind }
    }
    servers = each.value.cfg.server

    config = var.config
    image_size = "t3a.micro"
    vpc = local.vpc
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
