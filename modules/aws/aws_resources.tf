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
