
module "admin_provisioners" {
    source      = "../../provisioners"
    servers     = var.admin_servers
    names       = var.admin_names
    public_ips  = var.admin_public_ips
    private_ips = var.admin_private_ips
    region      = var.region

    aws_bot_access_key = var.aws_bot_access_key
    aws_bot_secret_key = var.aws_bot_secret_key

    known_hosts = var.known_hosts
    deploy_key_location = var.deploy_key_location
    root_domain_name = var.root_domain_name

    docker_compose_version = var.docker_compose_version
    docker_engine_install_url  = var.docker_engine_install_url
    consul_version         = var.consul_version

    # TODO: This might cause a problem when launching the 2nd admin server when swapping
    consul_lan_leader_ip = local.consul_lan_leader_ip
    consul_adv_addresses = local.consul_admin_adv_addresses

    role = "admin"
}

resource "null_resource" "change_admin_hostname" {
    count      = var.admin_servers

    provisioner "remote-exec" {
        inline = [
            "sudo hostnamectl set-hostname ${var.chef_server_url}",
            "sed -i 's/.*${var.server_name_prefix}-${var.region}.*/127.0.1.1 ${var.chef_server_url} ${element(var.admin_names, count.index)}/' /etc/hosts",
            "sed -i '$ a 127.0.1.1 ${var.chef_server_url} ${element(var.admin_names, count.index)}' /etc/hosts",
            "sed -i '$ a ${element(var.admin_public_ips, count.index)} ${var.chef_server_url} chef' /etc/hosts",
            "cat /etc/hosts"
        ]
        connection {
            host = element(var.admin_public_ips, count.index)
            type = "ssh"
        }
    }
}

resource "null_resource" "cron_admin" {
    count      = var.admin_servers > 0 ? var.admin_servers : 0
    depends_on = [module.admin_provisioners]

    provisioner "remote-exec" {
        inline = [ "mkdir -p /root/code/cron" ]
    }
    provisioner "file" {
        content = fileexists("${path.module}/template_files/cron/admin.tmpl") ? templatefile("${path.module}/template_files/cron/admin.tmpl", {
            gitlab_backups_enabled = var.gitlab_backups_enabled
            aws_bucket_region = var.aws_bucket_region
            aws_bucket_name = var.aws_bucket_name
        }) : ""
        destination = "/root/code/cron/admin.cron"
    }
    provisioner "remote-exec" {
        inline = [ "crontab /root/code/cron/admin.cron", "crontab -l" ]
    }
    connection {
        host = element(var.admin_public_ips, count.index)
        type = "ssh"
    }
}

resource "null_resource" "add_proxy_hosts" {
    count      = var.admin_servers
    depends_on = [module.admin_provisioners]

    #### TODO: Find a way to gradually migrate from blue -> green and vice versa vs
    ####   just sending all req suddenly from blue to green
    #### This way if the deployment was scuffed, it only affects X% of users whether
    ####   pre-determined  20/80 split etc. or part of slow rollout
    #### TODO: We already register a check/service with consul.. maybe have the app also
    ####   register its consul endpoints as well?

    triggers = {
        num_apps = length(keys(var.app_definitions))
    }

    provisioner "file" {
        content = <<-EOF

            %{ for APP in var.app_definitions }

                SUBDOMAIN_NAME=${APP["subdomain_name"]};
                GREEN_SERVICE=${APP["green_service"]};
                BLUE_SERVICE=${APP["blue_service"]};
                DEFAULT_ACTIVE=${APP["default_active"]};

                consul kv put apps/$SUBDOMAIN_NAME/green $GREEN_SERVICE
                consul kv put apps/$SUBDOMAIN_NAME/blue $BLUE_SERVICE
                consul kv put apps/$SUBDOMAIN_NAME/active $DEFAULT_ACTIVE
                consul kv put applist/$SUBDOMAIN_NAME

            %{ endfor }

            consul kv put domainname ${var.root_domain_name}
            consul kv put serverkey ${var.serverkey}
            consul kv put PG_PASSWORD ${var.pg_password}
            consul kv put DEV_PG_PASSWORD ${var.dev_pg_password}
            exit 0
        EOF
        destination = "/tmp/consulkeys.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/consulkeys.sh",
            "/tmp/consulkeys.sh",
            "rm /tmp/consulkeys.sh",
        ]
    }
    connection {
        host = element(var.admin_public_ips, count.index)
        type = "ssh"
    }
}

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

resource "null_resource" "install_gitlab" {
    count = var.admin_servers
    depends_on = [
        module.admin_provisioners,
        null_resource.change_admin_hostname,
        null_resource.change_admin_dns,
    ]

    # # After renewing certs possibly
    # sudo gitlab-ctl hup nginx

    # sudo mkdir -p /etc/gitlab/ssl/${var.root_domain_name};
    # sudo chmod 600 /etc/gitlab/ssl/${var.root_domain_name};

    # NOTE: With route53 as DNS over cloudflare, letsencrypt for gitlab cant verify right away
    #  as the dns change doesn't propagate as fast as cloudflare, wait a min or so before re-running.
    provisioner "remote-exec" {
        inline = [
            <<-EOF
                sudo apt-get update;
                sudo apt-get install -y ca-certificates curl openssh-server;
                echo postfix postfix/mailname string chef.${var.root_domain_name} | sudo debconf-set-selections
                echo postfix postfix/main_mailer_type string 'Internet Site' | sudo debconf-set-selections
                sudo apt-get install --assume-yes postfix;
                curl https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | sudo bash;
                sudo EXTERNAL_URL='http://gitlab.${var.root_domain_name}' apt-get install gitlab-ce=${var.gitlab_version};
                sed -i "s|http://gitlab|https://gitlab|" /etc/gitlab/gitlab.rb
                sed -i "s|https://registry.example.com|https://registry.${var.root_domain_name}|" /etc/gitlab/gitlab.rb
                sed -i "s|# registry_external_url|registry_external_url|" /etc/gitlab/gitlab.rb
                sed -i "s|# letsencrypt\['enable'\] = nil|letsencrypt\['enable'\] = true|" /etc/gitlab/gitlab.rb
                sed -i "s|# letsencrypt\['contact_emails'\] = \[\]|letsencrypt\['contact_emails'\] = \['${var.chef_email}'\]|" /etc/gitlab/gitlab.rb
                sed -i "s|# letsencrypt\['auto_renew'\]|letsencrypt\['auto_renew'\]|" /etc/gitlab/gitlab.rb
                sed -i "s|# letsencrypt\['auto_renew_hour'\]|letsencrypt\['auto_renew_hour'\]|" /etc/gitlab/gitlab.rb
                sed -i "s|# letsencrypt\['auto_renew_minute'\] = nil|letsencrypt\['auto_renew_minute'\] = 30|" /etc/gitlab/gitlab.rb
                sed -i "s|# letsencrypt\['auto_renew_day_of_month'\]|letsencrypt\['auto_renew_day_of_month'\]|" /etc/gitlab/gitlab.rb
                sleep 5;
                sudo gitlab-ctl reconfigure
            EOF


        ]
        # Enable pages
        # pages_external_url "http://pages.example.com/"
        # gitlab_pages['enable'] = false
    }
    # sudo chmod 755 /etc/gitlab/ssl;

    # ln -s /etc/letsencrypt/live/registry.${var.root_domain_name}/privkey.pem /etc/gitlab/ssl/registry.${var.root_domain_name}.key
    # ln -s /etc/letsencrypt/live/registry.${var.root_domain_name}/fullchain.pem /etc/gitlab/ssl/registry.${var.root_domain_name}.crt
    # "cp /etc/letsencrypt/live/${var.root_domain_name}/privkey.pem /etc/letsencrypt/live/${var.root_domain_name}/fullchain.pem /etc/gitlab/ssl/",

    connection {
        host = element(var.admin_public_ips, 0)
        type = "ssh"
    }
}


resource "null_resource" "restore_gitlab" {
    count = var.admin_servers
    depends_on = [
        module.admin_provisioners,
        null_resource.change_admin_hostname,
        null_resource.change_admin_dns,
        null_resource.install_gitlab
    ]

    provisioner "file" {
        content = file("${path.module}/template_files/importGitlab.sh")
        destination = "/root/code/scripts/importGitlab.sh"
    }

    provisioner "file" {
        content = file("${path.module}/template_files/backupGitlab.sh")
        destination = "/root/code/scripts/backupGitlab.sh"
    }

    provisioner "remote-exec" {
        inline = [
            <<-EOF
                chmod +x /root/code/scripts/importGitlab.sh;
                ${var.import_gitlab ? "bash /root/code/scripts/importGitlab.sh -r ${var.aws_bucket_region} -b ${var.aws_bucket_name};" : ""}

                GITLAB_BACKUPS_ENABLED=${var.gitlab_backups_enabled};
                if [ "$GITLAB_BACKUPS_ENABLED" != "true" ]; then
                    sed -i 's/BACKUPS_ENABLED=true/BACKUPS_ENABLED=false/g' /root/code/scripts/backupGitlab.sh;
                fi
                exit 0;
            EOF
        ]
    }

    connection {
        host = element(var.admin_public_ips, 0)
        type = "ssh"
    }
}


resource "null_resource" "sync_firewalls" {
    count = var.admin_servers
    depends_on = [
        module.admin_provisioners,
        null_resource.change_admin_hostname,
        null_resource.change_admin_dns,
        null_resource.install_gitlab,
        null_resource.restore_gitlab,
    ]

    provisioner "file" {
        content = <<-EOF
            check_docker() {
                LEADER_READY=$(consul kv get leader_ready);

                if [ "$LEADER_READY" = "true" ]; then
                    echo "Docker containers up";
                    exit 0;
                else
                    echo "Waiting 30 for docker containers";
                    sleep 30;
                    check_docker
                fi
            }

            check_consul() {
                LEADER_BOOTSTRAPPED=$(consul kv get leader_bootstrapped);
                DB_BOOTSTRAPPED=$(consul kv get db_bootstrapped);

                if [ "$LEADER_BOOTSTRAPPED" = "true" ] && [  "$DB_BOOTSTRAPPED" = "true" ]; then
                    consul kv put admin_ready true
                    echo "Admin firewall ready";
                    check_docker
                else
                    echo "Waiting 60 for bootstrapped leader & db";
                    sleep 60;
                    check_consul
                fi
            }


            check_consul
        EOF
        destination = "/tmp/sync_admin_firewall.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/sync_admin_firewall.sh",
            "/tmp/sync_admin_firewall.sh",
        ]
    }
    connection {
        host = element(var.admin_public_ips, count.index)
        type = "ssh"
    }
}

#### NOTE: Current problem is admin not allowing leader/db in though firewall, thus
####        a consul cluster leader not being chosen before the proxy_main service is brought online
#### NEW: null_resource.sync_firewalls is fixing this issue for now

resource "null_resource" "setup_letsencrypt" {
    count = var.leader_servers > 0 ? 1 : 0
    depends_on = [
        module.admin_provisioners,
        null_resource.change_admin_hostname,
        null_resource.change_admin_dns,
        null_resource.install_gitlab,
        null_resource.restore_gitlab,
        null_resource.change_proxy_dns,
        null_resource.sync_firewalls,
    ]

    triggers = {
        num_apps = length(keys(var.app_definitions))
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

    ## Intially setting up letsencrypt, proxy needs to be setup using http even though we launch it using https
    ## Currently the only workaround that is automated is relaunching the service by modifying
    ##   the compose file and redeploying
    provisioner "file" {
        content = <<-EOF
            HAS_PROXY_REPO=${ contains(keys(var.app_definitions), "proxy") }

            if [ "$HAS_PROXY_REPO" = "true" ]; then
                PROXY_STACK_NAME=${ contains(keys(var.app_definitions), "proxy") ? lookup(var.app_definitions["proxy"], "service_name" ) : "" }
                PROXY_REPO_NAME=${ contains(keys(var.app_definitions), "proxy") ? lookup(var.app_definitions["proxy"], "repo_name" ) : "" }

                SSL_CHECK=$(curl "https://${var.root_domain_name}");

                if [ $? -ne 0 ]; then
                    docker stack rm $PROXY_STACK_NAME
                    sed -i 's/LISTEN_ON_SSL:\s\+"true"/LISTEN_ON_SSL:      "false"/g' $HOME/repos/$PROXY_REPO_NAME/docker-compose.yml
                    docker stack deploy --compose-file $HOME/repos/$PROXY_REPO_NAME/docker-compose.yml $PROXY_STACK_NAME --with-registry-auth
                fi
            fi
        EOF
        destination = "/tmp/turnoff_proxy_ssl.sh"
        connection {
            host = element(var.lead_public_ips, 0)
            type = "ssh"
        }
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/turnoff_proxy_ssl.sh",
            "/tmp/turnoff_proxy_ssl.sh",
        ]

        connection {
            host = element(var.lead_public_ips, 0)
            type = "ssh"
        }
    }

    provisioner "file" {
        content = templatefile("${path.module}/template_files/letsencrypt_vars.tmpl", {
            app_definitions = var.app_definitions,
            fqdn = var.root_domain_name,
            email = var.chef_email,
            dry_run = false
        })
        destination = "/root/code/scripts/letsencrypt_vars.sh"
    }

    provisioner "file" {
        content = file("${path.module}/template_files/letsencrypt.tmpl")
        destination = "/root/code/scripts/letsencrypt.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /root/code/scripts/letsencrypt.sh",
            "export RUN_FROM_CRON=true; bash /root/code/scripts/letsencrypt.sh"
        ]
    }

    ## NOTE: Initial chef runs were having a problem communicating with chef.domain
    #   I believe its due to requests to chef.domain were https instead of http when always_use_https
    # provisioner "remote-exec" {
    #     # Turn cloudflare https redirect back on
    #     inline = <<-EOF
    #         ZONE_ID=${lookup(var.site_dns[0], "zone_id")};
    #         curl -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/settings/always_use_https" \
    #         -H "X-Auth-Email: ${var.cloudflare_email}" \
    #         -H "X-Auth-Key: ${var.cloudflare_auth_key}" \
    #         -H "Content-Type: application/json" \
    #         --data '{"value":"on"}';
    #         exit 0;
    #     EOF
    # }

    connection {
        host = element(var.admin_public_ips, count.index)
        type = "ssh"
    }

}

resource "null_resource" "add_keys" {
    count = var.leader_servers > 0 ? 1 : 0
    depends_on = [
        module.admin_provisioners,
        null_resource.change_admin_hostname,
        null_resource.change_admin_dns,
        null_resource.install_gitlab,
        null_resource.restore_gitlab,
        null_resource.change_proxy_dns,
        null_resource.sync_firewalls,
        null_resource.setup_letsencrypt,
    ]

    triggers = {
        num_apps = length(keys(var.app_definitions))
    }

    provisioner "file" {
        content = <<-EOF
            HAS_PROXY_REPO=${ contains(keys(var.app_definitions), "proxy") }

            if [ "$HAS_PROXY_REPO" = "true" ]; then
                PROXY_STACK_NAME=${ contains(keys(var.app_definitions), "proxy") ? lookup(var.app_definitions["proxy"], "service_name" ) : "" }
                PROXY_REPO_NAME=${ contains(keys(var.app_definitions), "proxy") ? lookup(var.app_definitions["proxy"], "repo_name" ) : "" }

                GREEN_SERVICE_NAME=${ contains(keys(var.app_definitions), "proxy") ? lookup(var.app_definitions["proxy"], "green_service" ) : "" };
                BLUE_SERVICE_NAME=${ contains(keys(var.app_definitions), "proxy") ? lookup(var.app_definitions["proxy"], "blue_service" ) : "" };
                DEFAULT_SERVICE_COLOR=${ contains(keys(var.app_definitions), "proxy") ? lookup(var.app_definitions["proxy"], "default_active" ) : "" };
                SERVICE_NAME=$GREEN_SERVICE_NAME;

                if [ "$DEFAULT_SERVICE_COLOR" = "blue" ]; then
                    SERVICE_NAME=$BLUE_SERVICE_NAME;
                fi

                SSL_CHECK=$(curl "https://${var.root_domain_name}");

                if [ $? -eq 0 ]; then
                    docker service update $SERVICE_NAME -d --force
                else
                    docker stack rm $PROXY_STACK_NAME
                    sed -i 's/LISTEN_ON_SSL:\s\+"false"/LISTEN_ON_SSL:      "true"/g' $HOME/repos/$PROXY_REPO_NAME/docker-compose.yml
                    docker stack deploy --compose-file $HOME/repos/$PROXY_REPO_NAME/docker-compose.yml $PROXY_STACK_NAME --with-registry-auth
                fi
            fi
        EOF
        destination = "/tmp/turnon_proxy_ssl.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/turnon_proxy_ssl.sh",
            "/tmp/turnon_proxy_ssl.sh",
        ]
    }

    connection {
        host = element(var.lead_public_ips, 0)
        type = "ssh"
    }
}
