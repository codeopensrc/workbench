# NOTE: Hopefully eliminated the circular dependency by not depending on the leader provisioners explicitly
resource "null_resource" "change_proxy_dns" {
    # We're gonna simply modify existing dns for now. To worry about creating/deleting/modifying
    # would require more effort for only slightly more flexability thats not needed at the moment
    count      = var.change_site_dns && var.leader_servers > 0 ? length(var.site_dns) : 0
    depends_on = [null_resource.start_docker_containers]

    triggers = {
        # v4
        # TODO: We must keep our servers to one swarm for the moment due to the limitation
        #    of the current "proxy" server running in a docker container. If we have multiple swarms,
        #    whatever swarm the DNS is routing to, itll only route to that swarm. We need an external
        #    load balancer/proxy to proxy requests either on a new software end or provider specific
        #    options (Digital Ocean, AWS, Azure) or Cloudflare.
        # For now, we only want to change the DNS to the very last server if the number of server changes
        #   regardless if we sizing up or down.
        update_proxy_dns = var.leader_servers
    }

    lifecycle {
        create_before_destroy = true
    }

    provisioner "remote-exec" {
        inline = [
            <<-EOF
                DNS_ID=${var.site_dns[count.index]["dns_id"]};
                ZONE_ID=${var.site_dns[count.index]["zone_id"]};
                URL=${var.site_dns[count.index]["url"]};
                IP=${element(var.lead_public_ips, var.leader_servers - 1)};

                # curl -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNS_ID" \
                # -H "X-Auth-Email: ${var.cloudflare_email}" \
                # -H "X-Auth-Key: ${var.cloudflare_auth_key}" \
                # -H "Content-Type: application/json" \
                # --data '{"type": "A", "name": "'$URL'", "content": "'$IP'", "proxied": false}';
                exit 0;
            EOF
        ]
        connection {
            host = element(var.lead_public_ips, 0)
            type = "ssh"
        }
    }
}


resource "null_resource" "create_app_subdomains" {
    # count      = var.leader_servers
    count      = 0
    depends_on = [null_resource.start_docker_containers]

    provisioner "remote-exec" {

        # A_RECORDS=(cert chef consul mongo.aws1 mongo.do1 pg.aws1 pg.do1 redis.aws1 redis.do1 www $ROOT_DOMAIN_NAME)
        # for A_RECORD in ${A_RECORDS[@]}; do
        #     curl -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
        #          -H "X-Auth-Email: ${cloudflare_email}" \
        #          -H "X-Auth-Key: ${cloudflare_auth_key}" \
        #          -H "Content-Type: application/json" \
        #          --data '{"type":"A","name":"'${A_RECORD}'","content":"127.0.0.1","ttl":1,"priority":10,"proxied":false}'
        # done

        inline = [
            <<-EOF

                ZONE_ID=${var.cloudflare_zone_id}
                ROOT_DOMAIN=${var.root_domain_name}

                %{ for APP in var.app_definitions }

                    CNAME_RECORD1=${APP["service_name"]};
                    CNAME_RECORD2=${APP["service_name"]}.dev;
                    CNAME_RECORD3=${APP["service_name"]}.db;
                    CNAME_RECORD4=${APP["service_name"]}.dev.db;

                    CREATE_SUBDOMAIN=${APP["create_subdomain"]};

                    if [ "$CREATE_SUBDOMAIN" = "true" ]; then

                        curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
                            -H "X-Auth-Email: ${var.cloudflare_email}" \
                            -H "X-Auth-Key: ${var.cloudflare_auth_key}" \
                            -H "Content-Type: application/json" \
                            --data '{"type":"CNAME","name":"'$CNAME_RECORD1'","content":"'$ROOT_DOMAIN'","ttl":1,"priority":10,"proxied":false}'

                        curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
                            -H "X-Auth-Email: ${var.cloudflare_email}" \
                            -H "X-Auth-Key: ${var.cloudflare_auth_key}" \
                            -H "Content-Type: application/json" \
                            --data '{"type":"CNAME","name":"'$CNAME_RECORD2'","content":"'$ROOT_DOMAIN'","ttl":1,"priority":10,"proxied":false}'

                        curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
                            -H "X-Auth-Email: ${var.cloudflare_email}" \
                            -H "X-Auth-Key: ${var.cloudflare_auth_key}" \
                            -H "Content-Type: application/json" \
                            --data '{"type":"CNAME","name":"'$CNAME_RECORD3'","content":"'$ROOT_DOMAIN'","ttl":1,"priority":10,"proxied":false}'

                        curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
                            -H "X-Auth-Email: ${var.cloudflare_email}" \
                            -H "X-Auth-Key: ${var.cloudflare_auth_key}" \
                            -H "Content-Type: application/json" \
                            --data '{"type":"CNAME","name":"'$CNAME_RECORD4'","content":"'$ROOT_DOMAIN'","ttl":1,"priority":10,"proxied":false}'
                    fi

                    sleep 2;

                %{ endfor }

                exit 0
            EOF
        ]
        connection {
            host = element(var.lead_public_ips, count.index)
            type = "ssh"
        }
    }
}



resource "null_resource" "sync_leader_with_admin_firewall" {
    count      = var.admin_servers
    depends_on = [null_resource.change_db_dns]

    provisioner "file" {
        content = <<-EOF
            check_consul() {

                consul kv put leader_bootstrapped true;

                ADMIN_READY=$(consul kv get admin_ready);

                if [ "$ADMIN_READY" = "true" ]; then
                    echo "Firewalls ready: Leader"
                    exit 0;
                else
                    echo "Waiting 15 for admin firewall";
                    sleep 15;
                    check_consul
                fi
            }

            check_consul
        EOF
        destination = "/tmp/sync_leader_firewall.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/sync_leader_firewall.sh",
            "/tmp/sync_leader_firewall.sh",
        ]
    }

    connection {
        host = element(var.lead_public_ips, count.index)
        type = "ssh"
    }
}


# TODO: Possibly utilize this to have a useful docker registry variable
# provisioner "file" {
#     content = <<-EOF
#         #!/bin/bash
#
#         export DOCKER_REGISTRY=""
#     EOF
#     destination = "/root/.bash_aliases"
# }
