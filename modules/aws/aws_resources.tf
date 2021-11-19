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

    admin_ip_public = local.admin_servers > 0 ? data.aws_instances.admin.public_ips[0] : ""
    admin_ip_private = local.admin_servers > 0 ? data.aws_instances.admin.private_ips[0] : ""
    consul_lan_leader_ip = (local.admin_servers > 0
        ? data.aws_instances.admin.private_ips[0]
        : (each.value.ind == 0 ? "" : data.aws_instances.lead.private_ips[0])
    )
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

    admin_ip_public = local.admin_servers > 0 ? data.aws_instances.admin.public_ips[0] : ""
    admin_ip_private = local.admin_servers > 0 ? data.aws_instances.admin.private_ips[0] : ""
    consul_lan_leader_ip = local.admin_servers > 0 ? data.aws_instances.admin.private_ips[0]: data.aws_instances.lead.private_ips[0]
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

    admin_ip_public = local.admin_servers > 0 ? data.aws_instances.admin.public_ips[0] : ""
    admin_ip_private = local.admin_servers > 0 ? data.aws_instances.admin.private_ips[0] : ""
    consul_lan_leader_ip = local.admin_servers > 0 ? data.aws_instances.admin.private_ips[0]: data.aws_instances.lead.private_ips[0]
}

### TODO: According to
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/instances
### Its better to use remote_state data source, will need to investigate 
# https://www.terraform.io/docs/language/state/remote-state-data.html

##NOTE: The sorting of the returned droplets actually matters to a degree
## We cannot rely on it as we cannot sort returned aws_instances and need to find out
##  if aws has a default return order
## This should all be a non-issue once ansible is up and running

data "aws_instances" "admin" {
    depends_on = [ module.admin.id, ]
    instance_tags = {
        Prefix = "${var.config.server_name_prefix}-${var.config.region}"
        Admin =  true
    }
    ### TODO: Filter to get matching ami and/or vpc
    #https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/instances
    #https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-instances.html
    #filter {
    #    name    = "image-id"
    #    values = [ module.admin.id ]
    #}
    #: (length(data.aws_ami_ids.latest.ids) > 0 ? data.aws_ami_ids.latest.ids[0] : data.aws_ami.new.id)
    #filter {
    #    vpc_id     = aws_vpc.terraform_vpc.id
    #    vpc_name = "${var.config.server_name_prefix}_vpc"
    #    resource "aws_vpc" "terraform_vpc" {
    #    name    = "name"
    #    values = [ "${var.config.server_name_prefix}-${var.config.region}" ]
    #}
}
data "aws_instances" "lead" {
    depends_on = [ module.admin.id, module.lead.id ]
    instance_tags = {
        Prefix = "${var.config.server_name_prefix}-${var.config.region}"
        Lead = true
    }
}
data "aws_instances" "db" {
    depends_on = [ module.admin.id, module.db.id ]
    instance_tags = {
        Prefix = "${var.config.server_name_prefix}-${var.config.region}"
        DB = true
    }
}
data "aws_instances" "build" {
    depends_on = [ module.admin.id, module.build.id ]
    instance_tags = {
        Prefix = "${var.config.server_name_prefix}-${var.config.region}"
        Build = true
    }
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
