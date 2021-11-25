## Cannot filter DROPLET snapshots by tags as they cannot be tagged (currently apparently)
## https://docs.digitalocean.com/reference/api/api-reference/#tag/Tags
data "digitalocean_images" "latest" {
    filter {
        key    = "name"
        values = [ var.image_name ]
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
    source             = "../../packer"
    build = length(data.digitalocean_images.latest.images) >= 1 ? false : true

    active_env_provider = var.config.active_env_provider
    role = var.servers.roles[0]

    aws_access_key = var.config.aws_access_key
    aws_secret_key = var.config.aws_secret_key
    aws_region = var.config.aws_region
    aws_key_name = var.config.aws_key_name
    aws_instance_type = ""

    do_token = var.config.do_token
    digitalocean_region = var.config.do_region
    digitalocean_image_size = var.image_size
    digitalocean_image_name = var.image_name

    packer_config = var.config.packer_config
}

data "digitalocean_images" "new" {
    depends_on = [ module.packer ]
    filter {
        key    = "name"
        values = [ var.image_name ]
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

## Purely to display if an image will be built or not
resource "null_resource" "image_status" {
    count = length(data.digitalocean_images.latest.images) >= 1 ? 0 : 1
    triggers = { needs_packer_build = length(data.digitalocean_images.latest.images) >= 1 ? false : true }
}

resource "digitalocean_droplet" "main" {
    name     = "${var.config.server_name_prefix}-${var.config.region}-${var.servers.roles[0]}-${substr(uuid(), 0, 4)}"
    #Priorty = Provided image id -> Latest image with matching filters -> Build if no matches
    image = (var.servers.image != ""
        ? var.servers.image
        : (length(data.digitalocean_images.latest.images) > 0
            ? data.digitalocean_images.latest.images[0].id : data.digitalocean_images.new.images[0].id)
    )
    region   = var.config.region
    size     = var.servers.size["digital_ocean"]
    ssh_keys = [var.config.do_ssh_fingerprint]
    tags = compact(flatten([
        contains(var.servers.roles, "admin") ? "gitlab-${replace(var.config.root_domain_name, ".", "-")}" : "",
        var.servers.roles,
        var.tags
    ]))

    lifecycle {
        ignore_changes = [name, tags]
    }

    vpc_uuid = var.vpc_uuid


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
