resource "digitalocean_droplet" "admin" {
    count    = var.active_env_provider == "digital_ocean" ? var.admin_servers : 0
    name     = "${var.server_name_prefix}-${var.region}-admin-${substr(uuid(), 0, 4)}"
    image    = "ubuntu-16-04-x64"
    region   = var.region
    size     = var.do_admin_size
    ssh_keys = [var.do_ssh_fingerprint]
    lifecycle {
        ignore_changes = [name]
    }
}

resource "digitalocean_droplet" "lead" {
    count    = var.active_env_provider == "digital_ocean" ? var.leader_servers : 0
    name     = "${var.server_name_prefix}-${var.region}-lead-${substr(uuid(), 0, 4)}"
    image    = "ubuntu-16-04-x64"
    region   = var.region
    size     = var.do_leader_size
    ssh_keys = [var.do_ssh_fingerprint]
    lifecycle {
        ignore_changes = [name]
    }
}

resource "digitalocean_droplet" "db" {
    count    = var.active_env_provider == "digital_ocean" ? var.db_servers : 0
    name     = "${var.server_name_prefix}-${var.region}-db-${substr(uuid(), 0, 4)}"
    image    = "ubuntu-16-04-x64"
    region   = var.region
    size     = var.do_db_size
    ssh_keys = [var.do_ssh_fingerprint]
    lifecycle {
        ignore_changes = [name]
    }
}

resource "digitalocean_droplet" "build" {
    count    = var.active_env_provider == "digital_ocean" ? var.build_servers : 0
    name     = "${var.server_name_prefix}-${var.region}-build-${substr(uuid(), 0, 4)}"
    image    = "ubuntu-16-04-x64"
    region   = var.region
    size     = var.do_build_size
    ssh_keys = [var.do_ssh_fingerprint]
    lifecycle {
        ignore_changes = [name]
    }

    depends_on = [
        digitalocean_droplet.lead
    ]
}

resource "digitalocean_droplet" "web" {
    count    = var.active_env_provider == "digital_ocean" ? var.web_servers : 0
    name     = "${var.server_name_prefix}-${var.region}-web-${substr(uuid(), 0, 4)}"
    image    = "ubuntu-16-04-x64"
    region   = var.region
    size     = var.do_web_size
    ssh_keys = [var.do_ssh_fingerprint]
    lifecycle {
        ignore_changes = [name]
    }

    depends_on = [
        digitalocean_droplet.lead
    ]
}

resource "digitalocean_droplet" "dev" {
    count    = var.active_env_provider == "digital_ocean" ? var.dev_servers : 0
    name     = "${var.server_name_prefix}-${var.region}-dev-${substr(uuid(), 0, 4)}"
    image    = "ubuntu-16-04-x64"
    region   = var.region
    size     = var.do_dev_size
    ssh_keys = [var.do_ssh_fingerprint]
    lifecycle {
        ignore_changes = [name]
    }

    depends_on = [
        digitalocean_droplet.lead
    ]
}



# This resource is to allow older servers to be imported into terraform to live
# along side our terraform configured servers without interfering with our current
# infrastructure and letting them stay running as-is
resource "digitalocean_droplet" "legacy" {
    count              = var.active_env_provider == "digital_ocean" ? var.legacy_servers : 0
    name               = "${var.server_name_prefix}-${var.region}-legacy-${count.index}"
    image              = "ubuntu-16-04-x64"
    region             = var.region
    size               = var.do_legacy_size
    ssh_keys           = [var.do_ssh_fingerprint]
    private_networking = true
    lifecycle {
        ignore_changes = [name]
    }
}

resource "digitalocean_droplet" "mongo" {
    count              = var.active_env_provider == "digital_ocean" ? var.mongo_servers : 0
    name               = "${var.server_name_prefix}-${var.region}-mongo-${count.index}"
    image              = "ubuntu-16-04-x64"
    region             = var.region
    size               = var.do_mongo_size
    ssh_keys           = [var.do_ssh_fingerprint]
    lifecycle {
        ignore_changes = [name]
    }
}

resource "digitalocean_droplet" "pg" {
    count              = var.active_env_provider == "digital_ocean" ? var.pg_servers : 0
    name               = "${var.server_name_prefix}-${var.region}-pg-${count.index}"
    image              = "ubuntu-16-04-x64"
    region             = var.region
    size               = var.do_pg_size
    ssh_keys           = [var.do_ssh_fingerprint]
    lifecycle {
        ignore_changes = [name]
    }
}

resource "digitalocean_droplet" "redis" {
    count              = var.active_env_provider == "digital_ocean" ? var.redis_servers : 0
    name               = "${var.server_name_prefix}-${var.region}-redis-${count.index}"
    image              = "ubuntu-16-04-x64"
    region             = var.region
    size               = var.do_redis_size
    ssh_keys           = [var.do_ssh_fingerprint]
    lifecycle {
        ignore_changes = [name]
    }
}
