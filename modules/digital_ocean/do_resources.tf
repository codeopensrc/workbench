## Cannot filter DROPLET snapshots by tags as they cannot be tagged (currently apparently)
## https://docs.digitalocean.com/reference/api/api-reference/#tag/Tags
data "digitalocean_images" "latest" {
    for_each = {
        for alias, image in local.packer_images:
        alias => image.name
    }
    filter {
        key    = "name"
        values = [ each.value ]
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
    source             = "../packer"
    for_each = {
        for alias, image in local.packer_images:
        alias => { name = image.name, size = image.size }
        if length(data.digitalocean_images.latest[alias].images) == 0
    }
    type = each.key
    packer_image_name = each.value.name
    packer_image_size = each.value.size

    active_env_provider = var.config.active_env_provider

    aws_access_key = var.config.aws_access_key
    aws_secret_key = var.config.aws_secret_key
    aws_region = var.config.aws_region
    aws_key_name = var.config.aws_key_name

    do_token = var.config.do_token
    digitalocean_region = var.config.do_region

    packer_config = var.config.packer_config
}

data "digitalocean_images" "new" {
    depends_on = [ module.packer ]
    for_each = {
        for alias, image in local.packer_images:
        alias => image.name
        if lookup(module.packer, alias, null) != null
    }
    filter {
        key    = "name"
        values = [ each.value ]
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

resource "time_static" "creation_time" {
    for_each = {
        for ind, cfg in local.cfg_servers:
        cfg.key => { cfg = cfg, ind = ind, role = cfg.role }
    }
}

resource "digitalocean_droplet" "main" {
    for_each = {
        for ind, cfg in local.cfg_servers:
        cfg.key => { cfg = cfg, ind = ind, role = cfg.role }
    }

    name     = "${var.config.server_name_prefix}-${var.config.region}-${each.value.role}-${substr(uuid(), 0, 4)}"
    #Priorty = Provided image id -> Latest image with matching filters -> Build if no matches
    image = (each.value.cfg.server.image != "" ? each.value.cfg.server.image
        : (length(data.digitalocean_images.latest[each.value.cfg.image_alias].images) > 0
            ? data.digitalocean_images.latest[each.value.cfg.image_alias].images[0].id : data.digitalocean_images.new[each.value.cfg.image_alias].images[0].id)
    )

    region   = var.config.region
    size     = each.value.cfg.server.size["digital_ocean"]
    ssh_keys = [var.config.do_ssh_fingerprint]
    tags = compact(flatten([
        each.value.role == "admin" ? "gitlab-${replace(var.config.root_domain_name, ".", "-")}" : "",
        each.value.cfg.server.roles,
        local.tags[each.value.role]
    ]))

    lifecycle {
        ignore_changes = [name, tags]
    }

    vpc_uuid = digitalocean_vpc.terraform_vpc.id

    provisioner "remote-exec" {
        inline = [ "cat /home/ubuntu/.ssh/authorized_keys | sudo tee /root/.ssh/authorized_keys" ]
        connection {
            host     = self.ipv4_address
            type     = "ssh"
            user     = "root"
            private_key = file(var.config.local_ssh_key_file)
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
