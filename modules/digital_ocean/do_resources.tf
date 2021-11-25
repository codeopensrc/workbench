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
}
