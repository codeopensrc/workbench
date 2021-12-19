resource "azurerm_resource_group" "main" {
    name     = "${var.config.server_name_prefix}-${var.config.az_resource_group}"
    location = var.config.az_region
}

data "azurerm_images" "latest" {
    for_each = {
        for alias, image in local.packer_images:
        alias => image.name
    }
    tags_filter = {
        name = each.value
    }
    resource_group_name = azurerm_resource_group.main.name
}

#module "packer" {
#    source             = "../packer"
#    for_each = {
#        for alias, image in local.packer_images:
#        alias => { name = image.name, size = image.size }
#        if length(data.azurerm_images.latest[alias].ids) == 0
#    }
#    type = each.key
#    packer_image_name = each.value.name
#    packer_image_size = each.value.size
#
#    active_env_provider = var.config.active_env_provider
#
#    aws_access_key = var.config.aws_access_key
#    aws_secret_key = var.config.aws_secret_key
#    aws_region = var.config.aws_region
#    aws_key_name = var.config.aws_key_name
#
#    do_token = var.config.do_token
#    digitalocean_region = var.config.do_region
#
#    packer_config = var.config.packer_config
#}

data "azurerm_images" "new" {
    for_each = {
        for alias, image in local.packer_images:
        alias => image.name
    }
    tags_filter = {
        name = each.value
    }
    resource_group_name = azurerm_resource_group.main.name
}

resource "time_static" "creation_time" {
    for_each = {
        for ind, cfg in local.cfg_servers:
        cfg.key => { cfg = cfg, ind = ind, role = cfg.role }
    }
}

resource "azurerm_linux_virtual_machine" "main" {
    for_each = {
        for ind, cfg in local.cfg_servers:
        cfg.key => { cfg = cfg, ind = ind, role = cfg.role }
    }
    name = "${var.config.server_name_prefix}-${var.config.region}-${each.value.role}-${substr(uuid(), 0, 4)}"
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location

    size = each.value.cfg.server.size
    admin_username   = var.config.az_admin_username
    disable_password_authentication = true
    network_interface_ids = [
        azurerm_network_interface.main[each.key].id,
    ]

    tags = {
        Domain = each.value.role == "admin" ? "gitlab-${replace(var.config.root_domain_name, ".", "-")}" : ""
    }

    lifecycle {
        ignore_changes= [ name, tags ]
    }

    admin_ssh_key {
        username   = var.config.az_admin_username
        public_key = file("${var.config.local_ssh_key_file}.pub")
    }

    os_disk {
        caching              = "ReadWrite"
        storage_account_type = "Standard_LRS"
    }

    #Priorty = Provided image id -> Latest image with matching filters -> Build if no matches
    #source_image_id = (each.value.cfg.server.image != "" ? each.value.cfg.server.image
    #    : (length(data.azurerm_images.latest[each.value.cfg.image_alias].images) > 0
    #        ? data.azurerm_images.latest[each.value.cfg.image_alias].images[0].id : data.azurerm_images.new[each.value.cfg.image_alias].images[0].id)
    #)

    ## TODO: Temporary until packer
    source_image_reference {
        publisher = var.config.packer_config.azure_image_os[var.config.az_region].publisher
        offer     = var.config.packer_config.azure_image_os[var.config.az_region].offer
        sku       = var.config.packer_config.azure_image_os[var.config.az_region].sku
        version   = var.config.packer_config.azure_image_os[var.config.az_region].version
    }

    provisioner "remote-exec" {
        inline = [ "cat /home/${var.config.az_admin_username}/.ssh/authorized_keys | sudo tee /root/.ssh/authorized_keys" ]
        connection {
            host     = self.public_ip_address
            type     = "ssh"
            user     = self.admin_username
            private_key = file(var.config.local_ssh_key_file)
        }
    }
    provisioner "local-exec" {
        command = "ssh-keyscan -H ${self.public_ip_address} >> ~/.ssh/known_hosts"
    }

    provisioner "local-exec" {
        when = destroy
        command = <<-EOF
            ssh-keygen -R ${self.public_ip_address};

            if [ "${terraform.workspace}" != "default" ]; then
                ${self.tags.Domain != "" ? "ssh-keygen -R \"${replace(regex("gitlab-[a-z]+-[a-z]+", self.tags.Domain), "-", ".")}\"" : ""}
                echo "Not default"
            fi

            exit 0;
        EOF
        on_failure = continue
    }
}


