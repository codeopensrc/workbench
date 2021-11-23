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

resource "null_resource" "image_status" {
    count = length(data.digitalocean_images.latest.images) >= 1 ? 0 : 1
    triggers = { needs_packer_build = length(data.digitalocean_images.latest.images) >= 1 ? false : true }
}
resource "random_uuid" "server" {}

resource "digitalocean_droplet" "main" {
    name     = "${var.config.server_name_prefix}-${var.config.region}-${var.servers.roles[0]}-${substr(random_uuid.server.id, 0, 4)}"
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
        "${var.config.server_name_prefix}-${var.config.region}-${var.servers.roles[0]}-${substr(random_uuid.server.id, 0, 4)}",
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

    ##TODO: Will be replaced once runners handled via ansible
    provisioner "remote-exec" {
        when = destroy
        inline = [
            <<-EOF
                consul leave;
                if [ "${length( regexall("build", join(",", self.tags)) ) > 0}" = "true" ]; then
                    chmod +x /home/gitlab-runner/rmscripts/rmrunners.sh;
                    bash /home/gitlab-runner/rmscripts/rmrunners.sh;
                fi
                if [ "${length( regexall("lead", join(",", self.tags)) ) > 0}" = "true" ]; then
                    chmod +x /home/gitlab-runner/rmscripts/rmrunners.sh;
                    bash /home/gitlab-runner/rmscripts/rmrunners.sh;
                fi
            EOF
        ]
        on_failure = continue
        connection {
            host     = self.ipv4_address
            type     = "ssh"
            user     = "root"
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


module "consul" {
    source = "../../consul"

    role = var.servers.roles[0]
    region = var.config.region
    datacenter_has_admin = var.admin_ip_public != "" || var.consul_lan_leader_ip != "" ? true : false
    consul_lan_leader_ip = var.consul_lan_leader_ip != "" ? var.consul_lan_leader_ip : digitalocean_droplet.main.ipv4_address_private
    #consul_wan_leader_ip = var.consul_wan_leader_ip

    name = digitalocean_droplet.main.name
    public_ip = digitalocean_droplet.main.ipv4_address
    private_ip = digitalocean_droplet.main.ipv4_address_private
}
