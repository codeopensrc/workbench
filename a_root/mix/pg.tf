
module "pg_provisioners" {
    source      = "../../provisioners"
    servers     = var.pg_servers
    names       = var.pg_names
    public_ips  = var.pg_public_ips
    private_ips = var.pg_private_ips
    region      = var.region

    aws_bot_access_key = var.aws_bot_access_key
    aws_bot_secret_key = var.aws_bot_secret_key

    deploy_key_location = var.deploy_key_location

    docker_engine_install_url = var.docker_engine_install_url
    consul_version        = var.consul_version

    consul_lan_leader_ip = (length(var.admin_public_ips) > 0
        ? element(concat(var.admin_public_ips, [""]), 0)
        : element(concat(var.lead_public_ips, [""]), 0))

    role = "db_pg"
    db_backups_enabled = var.db_backups_enabled
}


resource "null_resource" "import_pg_db" {
    # count      = var.import_dbs && var.pg_servers > 0 ? var.pg_servers : 0
    count      = 0
    depends_on = [module.pg_provisioners]

    provisioner "remote-exec" {
        inline = [
            "bash ~/import_pg_db.sh"
        ]
        connection {
            host = element(var.pg_public_ips, count.index)
            type = "ssh"
        }
    }
}

resource "null_resource" "change_pg_dns" {
    # We're gonna simply modify existing dns for now. To worry about creating/deleting/modifying
    # would require more effort for only slightly more flexability thats not needed at the moment
    # count      = var.change_db_dns && var.pg_servers > 0 ? var.pg_servers : 0
    count      = 0
    depends_on = [null_resource.import_pg_db]

    triggers = {
        update_pg_dns = element(var.pg_ids, var.pg_servers - 1)
    }

    lifecycle {
        create_before_destroy = true
    }

    provisioner "remote-exec" {
        inline = [
            <<-EOF
                DNS_ID=${var.db_dns["pg"]["dns_id"]};
                ZONE_ID=${var.db_dns["pg"]["zone_id"]};
                URL=${var.db_dns["pg"]["url"]};
                IP=${element(var.pg_public_ips, var.pg_servers - 1)};

                curl -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNS_ID" \
                -H "X-Auth-Email: ${var.cloudflare_email}" \
                -H "X-Auth-Key: ${var.cloudflare_auth_key}" \
                -H "Content-Type: application/json" \
                --data '{"type": "A", "name": "'$URL'", "content": "'$IP'", "proxied": false}';
            EOF
        ]
        connection {
            host = element(var.pg_public_ips, var.pg_servers - 1)
            type = "ssh"
        }
    }
}
