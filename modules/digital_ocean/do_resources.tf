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

    az_subscriptionId = var.config.az_subscriptionId
    az_tenant = var.config.az_tenant
    az_appId = var.config.az_appId
    az_password = var.config.az_password
    az_region = var.config.az_region
    az_resource_group = var.config.az_resource_group

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

    name = (each.value.role == "admin"
        ? "gitlab.${var.config.root_domain_name}"
        : "${var.config.server_name_prefix}-${var.config.region}-${each.value.role}-${substr(uuid(), 0, 4)}")
    #Priorty = Provided image id -> Latest image with matching filters -> Build if no matches
    image = (each.value.cfg.server.image != "" ? each.value.cfg.server.image
        : (length(data.digitalocean_images.latest[each.value.cfg.image_alias].images) > 0
            ? data.digitalocean_images.latest[each.value.cfg.image_alias].images[0].id : data.digitalocean_images.new[each.value.cfg.image_alias].images[0].id)
    )

    region   = var.config.region
    size     = each.value.cfg.server.size
    ssh_keys = [var.config.do_ssh_fingerprint]
    ## Maybe start tagging with just root_domain_name
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
        inline = [ 
            "cat /home/ubuntu/.ssh/authorized_keys | sudo tee /root/.ssh/authorized_keys",
            "echo \"DO_CLUSTER_VPC_ID=${digitalocean_vpc.terraform_vpc.id}\" >> /etc/environment",
        ]
        connection {
            host     = self.ipv4_address
            type     = "ssh"
            user     = "root"
            private_key = file(var.config.local_ssh_key_file)
        }
    }
    provisioner "local-exec" {
        command = "ssh-keyscan -H ${self.ipv4_address} >> ~/.ssh/known_hosts"
    }
    provisioner "local-exec" {
        when = destroy
        command = <<-EOF
            ssh-keygen -R ${self.ipv4_address};

            if [ "${terraform.workspace}" != "default" ]; then
                echo "Not default namespace, removing hostnames from known_hosts"
                if [ "${contains(self.tags, "admin")}" = "true" ]; then
                    echo "Has admin tag"
                    DOMAIN=${length(regexall("gitlab-[a-z]+-[a-z]+", join(",", self.tags))) > 0 ? replace(regex("gitlab-[a-z]+-[a-z]+", join(",", self.tags)), "-", ".") : ""};
                    ROOT_DOMAIN=$(echo "$DOMAIN" | sed "s/gitlab\.//");

                    echo "Removing $DOMAIN from known_hosts";
                    ssh-keygen -R "$DOMAIN";
                    echo "Removing $ROOT_DOMAIN from known_hosts";
                    ssh-keygen -R "$ROOT_DOMAIN";
                 else
                    echo "Does not have admin tag"
                fi
            fi
            exit 0;
        EOF
        on_failure = continue
    }
}

## Creating LB here if kubernetes so dns can point to the ip for single node atm
## TODO: Logic in kubernetes module to update DNS to nginx ingress controller 
## provisioned loadbalancer IP if workers > 0
## Otherwise we could _maybe_ just have the loadbalancer ignore all changes
## We'd also have to export the load balancer id which im not fond of
resource "digitalocean_loadbalancer" "main" {
    count  = local.use_lb || local.use_kube_managed_lb ? 1 : 0
    name   = local.lb_name
    region = var.config.region

    lifecycle {
        ignore_changes = [name]
    }

    forwarding_rule {
        entry_port      = 80
        entry_protocol  = "tcp"
        target_port     = local.lb_http_nodeport
        target_protocol = "tcp"
    }
    forwarding_rule {
        entry_port      = 443
        entry_protocol  = "tcp"
        target_port     = local.lb_https_nodeport
        target_protocol = "tcp"
    }
    dynamic "forwarding_rule" {
        for_each = local.lb_udp_nodeports
        content {
            entry_port      = forwarding_rule.key
            entry_protocol  = "udp"
            target_port     = forwarding_rule.value
            target_protocol = "udp"
        }
    }
    dynamic "forwarding_rule" {
        for_each = local.lb_tcp_nodeports
        content {
            entry_port      = forwarding_rule.key
            entry_protocol  = "tcp"
            target_port     = forwarding_rule.value
            target_protocol = "tcp"
        }
    }

    healthcheck {
        check_interval_seconds = 3
        port     = local.lb_http_nodeport
        protocol = "tcp"
    }
    #enable_proxy_protocol = true
    vpc_uuid = digitalocean_vpc.terraform_vpc.id

    ##TODO: If nginx takes over it wipes droplet ids atm
    droplet_ids = (local.use_kube_managed_lb
        ? [ for name, attr in digitalocean_droplet.main: attr.id ]
        : []
    )
}
