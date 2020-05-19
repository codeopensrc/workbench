
module "redis_provisioners" {
    source      = "../../provisioners"
    servers     = var.redis_servers
    names       = var.redis_names
    public_ips  = var.redis_public_ips
    private_ips = var.redis_private_ips
    region      = var.region

    aws_bot_access_key = var.aws_bot_access_key
    aws_bot_secret_key = var.aws_bot_secret_key

    deploy_key_location = var.deploy_key_location
    misc_repos      = var.misc_repos
    chef_local_dir  = var.chef_local_dir
    chef_client_ver = var.chef_client_ver

    docker_engine_version = var.docker_engine_version
    consul_version        = var.consul_version

    consul_lan_leader_ip = (length(var.admin_public_ips) > 0
        ? element(concat(var.admin_public_ips, [""]), 0)
        : element(concat(var.lead_public_ips, [""]), 0))

    role = "db_redis"
    db_backups_enabled = var.db_backups_enabled
}


resource "null_resource" "import_redis_db" {
    # count      = var.import_dbs && var.redis_servers > 0 ? var.redis_servers : 0
    count      = 0
    depends_on = [module.redis_provisioners]

    provisioner "remote-exec" {
        inline = [
            "bash ~/import_redis_db.sh; exit 0"
        ]
        connection {
            host = element(var.redis_public_ips, count.index)
            type = "ssh"
        }
    }
}


resource "null_resource" "change_redis_dns" {
    # We're gonna simply modify existing dns for now. To worry about creating/deleing
    # would require more effort for only slightly more flexability thats not needed at the moment
    # count      = var.change_db_dns && var.redis_servers > 0 ? var.redis_servers : 0
    count      = 0
    depends_on = [null_resource.import_redis_db]

    triggers = {
        update_redis_dns = element(var.redis_ids, var.redis_servers - 1)
    }

    lifecycle {
        create_before_destroy = true
    }

    provisioner "remote-exec" {
        inline = [
            <<-EOF
                DNS_ID=${var.db_dns["redis"]["dns_id"]};
                ZONE_ID=${var.db_dns["redis"]["zone_id"]};
                URL=${var.db_dns["redis"]["url"]};
                IP=${element(var.redis_public_ips, var.redis_servers - 1)};

                curl -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNS_ID" \
                -H "X-Auth-Email: ${var.cloudflare_email}" \
                -H "X-Auth-Key: ${var.cloudflare_auth_key}" \
                -H "Content-Type: application/json" \
                --data '{"type": "A", "name": "'$URL'", "content": "'$IP'", "proxied": false}';
            EOF
        ]
        connection {
            host = element(var.redis_public_ips, var.redis_servers - 1)
            type = "ssh"
        }
    }
}
