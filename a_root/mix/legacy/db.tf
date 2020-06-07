resource "null_resource" "change_db_dns" {
    # We're gonna simply modify existing dns for now. To worry about creating/deleting/modifying
    # would require more effort for only slightly more flexability thats not needed at the moment
    count = var.change_db_dns && var.db_servers > 0 ? length(keys(var.db_dns)) : 0
    depends_on = [
        null_resource.import_dbs,
    ]

    triggers = {
        update_db_dns = element(var.db_ids, var.db_servers - 1)
    }

    lifecycle {
        create_before_destroy = true
    }

    provisioner "remote-exec" {
        inline = [
            <<-EOF
                DNS_ID=${var.db_dns[element(keys(var.db_dns), count.index)]["dns_id"]};
                ZONE_ID=${var.db_dns[element(keys(var.db_dns), count.index)]["zone_id"]};
                URL=${var.db_dns[element(keys(var.db_dns), count.index)]["url"]};
                IP=${element(var.db_public_ips, var.db_servers - 1)};

                # curl -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNS_ID" \
                # -H "X-Auth-Email: ${var.cloudflare_email}" \
                # -H "X-Auth-Key: ${var.cloudflare_auth_key}" \
                # -H "Content-Type: application/json" \
                # --data '{"type": "A", "name": "'$URL'", "content": "'$IP'", "proxied": false}';
            EOF
        ]
        connection {
            host = element(var.db_public_ips, var.db_servers - 1)
            type = "ssh"
        }
    }
}





resource "null_resource" "db_check" {
    count      = var.admin_servers > 0 ? 1 : 0
    depends_on = [ null_resource.import_dbs ]

    provisioner "file" {
        content = <<-EOF
            check_consul() {



                ADMIN_READY=$(consul kv get admin_ready);

                if [ "$ADMIN_READY" = "true" ]; then
                    echo "Firewalls ready: DB"
                    exit 0;
                else
                    echo "Waiting 30 for admin firewall";
                    sleep 30;
                    check_consul
                fi
            }

            check_consul
        EOF
        destination = "/tmp/db_check.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/db_check.sh",
            "/tmp/db_check.sh",
        ]
    }

    connection {
        host = element(var.db_public_ips, count.index)
        type = "ssh"
    }
}
