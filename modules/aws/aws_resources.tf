
data "aws_ami_ids" "latest" {
    for_each = {
        for alias, image in local.packer_images:
        alias => image.name
    }
    owners = ["self"]
    filter {
        name = "name"
        values = [ each.value ]
    }
    filter {
        name   = "tag:aws_key_name"
        values = [ var.config.aws_key_name ]
    }
}

module "packer" {
    source             = "../packer"
    for_each = {
        for alias, image in local.packer_images:
        alias => { name = image.name, size = image.size }
        if length(data.aws_ami_ids.latest[alias].ids) == 0
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

    az_subscriptionId = var.config.az_subscriptionId
    az_tenant = var.config.az_tenant
    az_appId = var.config.az_appId
    az_password = var.config.az_password
    az_region = var.config.az_region
    az_resource_group = var.config.az_resource_group

    packer_config = var.config.packer_config
}

data "aws_ami" "new" {
    depends_on = [ module.packer ]
    most_recent = true
    for_each = {
        for alias, image in local.packer_images:
        alias => image.name
        if lookup(module.packer, alias, null) != null
    }

    owners = ["self"]

    filter {
        name = "name"
        values = [ each.value ]
    }
    filter {
        name   = "tag:aws_key_name"
        values = [ var.config.aws_key_name ]
    }
}

resource "time_static" "creation_time" {
    for_each = {
        for ind, cfg in local.cfg_servers:
        cfg.key => { cfg = cfg, ind = ind, role = cfg.role }
    }
}

resource "aws_instance" "main" {
    for_each = {
        for ind, cfg in local.cfg_servers:
        cfg.key => { cfg = cfg, ind = ind, role = cfg.role }
    }

    key_name = var.config.aws_key_name
    #Priorty = Provided image id -> Latest image with matching filters -> Build if no matches
    ami = (each.value.cfg.server.image != "" ? each.value.cfg.server.image
        : (length(data.aws_ami_ids.latest[each.value.cfg.image_alias].ids) > 0
            ? data.aws_ami_ids.latest[each.value.cfg.image_alias].ids[0] : data.aws_ami.new[each.value.cfg.image_alias].id)
    )

    instance_type = each.value.cfg.server.size

    tags = {
        Name = "${var.config.server_name_prefix}-${var.config.region}-${each.value.role}-${substr(uuid(), 0, 4)}",
        Domain = each.value.role == "admin" ? "gitlab-${replace(var.config.root_domain_name, ".", "-")}" : ""
        Roles = join(",", each.value.cfg.server.roles)
    }
    lifecycle {
        ignore_changes= [ tags ]
    }

    root_block_device {
        volume_size = each.value.cfg.server.disk_size
    }

    subnet_id              = aws_subnet.public_subnet.id

    vpc_security_group_ids = compact([
        aws_security_group.default_ports.id,
        aws_security_group.ext_remote.id,

        contains(each.value.cfg.server.roles, "admin") ? aws_security_group.admin_ports.id : "",
        contains(each.value.cfg.server.roles, "lead") ? aws_security_group.app_ports.id : "",

        contains(each.value.cfg.server.roles, "db") ? aws_security_group.db_ports.id : "",
        contains(each.value.cfg.server.roles, "db") ? aws_security_group.ext_db.id : "",
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
    provisioner "local-exec" {
        command = "ssh-keyscan -H ${self.public_ip} >> ~/.ssh/known_hosts"
    }
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
