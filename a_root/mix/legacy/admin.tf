# TODO: Deprecate/Use only if cloudflare as DNS
resource "null_resource" "change_admin_dns" {
    # We're gonna simply modify existing dns for now. To worry about creating/deleting/modifying
    # would require more effort for only slightly more flexability thats not needed at the moment
    count = var.change_admin_dns && var.admin_servers > 0 ? length(var.admin_dns) : 0
    depends_on = [
        module.admin_provisioners,
        null_resource.change_admin_hostname
    ]

    triggers = {
        #### NOTE: WE NEED TO CHANGE THE DNS TO THE NEW MACHINE OR WE CANT PROVISION ANYTHING
        ####   We should make a backup chef domain to use and implement logic to allow
        ####   more than one chef dns/domain in order for it to be a fairly seemless
        ####   swap with ability to roll back in case of errors
        update_admin_dns = (length(var.admin_names) > 1
            ? element(concat(var.admin_names, [""]), var.admin_servers - 1)
            : element(concat(var.admin_names, [""]), 0))
    }

    provisioner "remote-exec" {
        inline = [
            <<-EOF
                DNS_ID=${var.admin_dns[count.index]["dns_id"]};
                ZONE_ID=${var.admin_dns[count.index]["zone_id"]};
                URL=${var.admin_dns[count.index]["url"]};
                IP=${element(var.admin_public_ips,var.admin_servers - 1)};

                # curl -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNS_ID" \
                # -H "X-Auth-Email: ${var.cloudflare_email}" \
                # -H "X-Auth-Key: ${var.cloudflare_auth_key}" \
                # -H "Content-Type: application/json" \
                # --data '{"type": "A", "name": "'$URL'", "content": "'$IP'", "proxied": false}';
                exit 0;
            EOF
        ]
        connection {
            host = element(var.admin_public_ips,var.admin_servers - 1)
            type = "ssh"
        }
    }
}





provisioner "file" {
    content = <<-EOF
        ZONE_ID=${var.site_dns[0]["zone_id"]};
        curl -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/settings/always_use_https" \
        -H "X-Auth-Email: ${var.cloudflare_email}" \
        -H "X-Auth-Key: ${var.cloudflare_auth_key}" \
        -H "Content-Type: application/json" \
        --data '{"value":"off"}';
        exit 0;
    EOF
    destination = "/tmp/turnof_cloudflare_ssl.sh"
}

provisioner "remote-exec" {
    # Turn off cloudflare https redirect temporarily when getting SSL using letsencrypt
    inline = [
        "chmod +x /tmp/turnof_cloudflare_ssl.sh",
    ]
    # "/tmp/turnof_cloudflare_ssl.sh",
}
