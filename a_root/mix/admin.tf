
module "admin_provisioners" {
    source      = "../../provisioners"
    servers     = var.admin_servers
    names       = var.admin_names
    public_ips  = var.admin_public_ips
    private_ips = var.admin_private_ips
    region      = var.region

    aws_bot_access_key = var.aws_bot_access_key
    aws_bot_secret_key = var.aws_bot_secret_key

    deploy_key_location = var.deploy_key_location
    root_domain_name = var.root_domain_name
    chef_local_dir  = var.chef_local_dir
    chef_client_ver = var.chef_client_ver

    docker_compose_version = var.docker_compose_version
    docker_engine_install_url  = var.docker_engine_install_url
    consul_version         = var.consul_version

    # TODO: This might cause a problem when launching the 2nd admin server when swapping
    consul_lan_leader_ip = element(concat(var.admin_public_ips, [""]), 0)

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
        content = fileexists("${path.module}/template_files/cron/admin.tmpl") ? file("${path.module}/template_files/cron/admin.tmpl") : ""
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

    provisioner "file" {
        content = <<-EOF

            %{ for APP in var.app_definitions }

                SERVICE_NAME=${APP["service_name"]};
                GREEN_SERVICE=${APP["green_service"]};
                BLUE_SERVICE=${APP["blue_service"]};
                DEFAULT_ACTIVE=${APP["default_active"]};

                consul kv put apps/$SERVICE_NAME/green $GREEN_SERVICE
                consul kv put apps/$SERVICE_NAME/blue $BLUE_SERVICE
                consul kv put apps/$SERVICE_NAME/active $DEFAULT_ACTIVE
                consul kv put applist/$SERVICE_NAME

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
        destination = "/tmp/importGitlab.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/importGitlab.sh",
            (var.import_gitlab
                ? "/tmp/importGitlab.sh -r ${var.aws_bucket_region} -b ${var.aws_bucket_name}"
                : "echo 0"),
        ]
    }

    connection {
        host = element(var.admin_public_ips, 0)
        type = "ssh"
    }
}

# TODO: Get rid of chef over ansible
resource "null_resource" "install_chef_server" {
    count = var.admin_servers
    depends_on = [
        module.admin_provisioners,
        null_resource.change_admin_hostname,
        null_resource.change_admin_dns,
        null_resource.install_gitlab,
        null_resource.restore_gitlab,
    ]

    # Some helper commands to re-run/re-provision chef
    # chef-server-ctl upgrade
    # chef-server-ctl start
    # chef-server-ctl cleanup
    # "echo 'nginx["'"non_ssl_port"'"]=${var.chef_server_http_port}' /etc/opscode/chef-server.rb",
    # "echo 'nginx["ssl_port"]=${var.chef_server_https_port}' /etc/opscode/chef-server.rb",
    provisioner "file" {
        content = <<-EOF
            nginx['non_ssl_port'] = ${var.chef_server_http_port}
            nginx['ssl_port'] = ${var.chef_server_https_port}
            nginx['url'] = 'https://chef.${var.root_domain_name}:${var.chef_server_https_port}/'
            nginx['server_name'] = 'chef.${var.root_domain_name}'
            bookshelf['vip_port'] = ${var.chef_server_https_port}
            bookshelf['external_url'] = 'https://chef.${var.root_domain_name}:${var.chef_server_https_port}'
            opscode_erchef['base_resource_url'] = 'https://chef.${var.root_domain_name}:${var.chef_server_https_port}'
        EOF
        destination = "/tmp/chef-server.rb"
    }

    provisioner "remote-exec" {
        inline = [
            "curl -L https://packages.chef.io/files/stable/chef-server/${var.chef_server_ver}/ubuntu/${var.ubuntu_ver}/chef-server-core_${var.chef_server_ver}-1_amd64.deb > /tmp/chef-server-core-${var.chef_server_ver}.deb",
            "sudo dpkg -i /tmp/chef-server-core-${var.chef_server_ver}.deb",
            "cp /tmp/chef-server.rb /etc/opscode/chef-server.rb",
            "chef-server-ctl reconfigure",
            "mkdir -p ${var.chef_remote_dir}",
            "chef-server-ctl user-create ${var.chef_user} ${var.chef_fn} ${var.chef_ln} ${var.chef_email} '${var.chef_pw}' --filename ${var.chef_remote_dir}/${var.chef_user}.pem",
            "chef-server-ctl org-create ${var.chef_org_short} '${var.chef_org_full}' --association_user ${var.chef_org_user} --filename ${var.chef_remote_dir}/${var.chef_org_short}-validator.pem"
        ]
    }
    connection {
        host = element(var.admin_public_ips, count.index)
        type = "ssh"
    }
}



resource "null_resource" "install_chef_dk" {
    count = var.admin_servers
    depends_on = [
        module.admin_provisioners,
        null_resource.change_admin_hostname,
        null_resource.change_admin_dns,
        null_resource.install_gitlab,
        null_resource.restore_gitlab,
        null_resource.install_chef_server,
    ]

    provisioner "remote-exec" {
        inline = [
            "curl -L https://packages.chef.io/files/stable/chefdk/${var.chef_dk_ver}/ubuntu/${var.ubuntu_ver}/chefdk_${var.chef_dk_ver}-1_amd64.deb > /tmp/chefdk_${var.chef_dk_ver}-1_amd64.deb",
            "sudo dpkg -i /tmp/chefdk_${var.chef_dk_ver}-1_amd64.deb",
            <<-EOF
                echo 'eval "$(chef shell-init bash)"' >> ~/.bash_profile
            EOF
        ]
        connection {
            host = element(var.admin_public_ips, count.index)
            type = "ssh"
        }
    }

}


resource "null_resource" "provision_chef_dk" {
    count = var.admin_servers
    depends_on = [
        module.admin_provisioners,
        null_resource.change_admin_hostname,
        null_resource.change_admin_dns,
        null_resource.install_gitlab,
        null_resource.restore_gitlab,
        null_resource.install_chef_server,
        null_resource.install_chef_dk,
    ]

    provisioner "file" {
        content = <<-EOF
            current_dir = File.dirname(__FILE__)
            log_level                :info
            log_location             STDOUT
            node_name                "${var.chef_user}"
            client_key               "#{current_dir}/${var.chef_user}.pem"
            validation_client_name   "${var.chef_org_short}-validator"
            validation_key           "#{current_dir}/${var.chef_org_short}-validator.pem"
            chef_server_url          "https://${var.chef_server_url}:${var.chef_server_https_port}/organizations/${var.chef_org_short}"
            syntax_check_cache_path  "#{ENV['HOME']}/.chef/syntaxcache"
            cookbook_path            ["#{current_dir}/../cookbooks"]
        EOF
        destination = "${var.chef_remote_dir}/knife.rb"
    }

    provisioner "remote-exec" {
        inline = [
            "cd ${var.chef_remote_dir} && knife ssl fetch",
        ]
    }

    provisioner "local-exec" {
        # Do some stuff to pull down the chef pem file and place into local directory
        command = <<-EOF
            NUM_BACKUPS=$(ls -la | grep .chef.backup | wc -l)
            mv ${var.chef_local_dir} ${var.chef_local_dir}.backup-$NUM_BACKUPS
            mkdir -p ${var.chef_local_dir};
            docker-machine scp ${element(var.admin_names, count.index)}:${var.chef_remote_dir}/${var.chef_user}.pem ${var.chef_local_dir}/${var.chef_user}.pem;
            docker-machine scp ${element(var.admin_names, count.index)}:${var.chef_remote_dir}/${var.chef_org_short}-validator.pem ${var.chef_local_dir}/${var.chef_org_short}-validator.pem;
            docker-machine scp ${element(var.admin_names, count.index)}:${var.chef_remote_dir}/knife.rb ${var.chef_local_dir}/knife.rb;
            knife ssl fetch --config ${var.chef_local_dir}/knife.rb
        EOF

    }

    connection {
        host = element(var.admin_public_ips, count.index)
        type = "ssh"
    }
}


resource "null_resource" "upload_chef_cookbooks" {
    count = var.admin_servers
    depends_on = [
        module.admin_provisioners,
        null_resource.change_admin_hostname,
        null_resource.change_admin_dns,
        null_resource.install_gitlab,
        null_resource.restore_gitlab,
        null_resource.install_chef_server,
        null_resource.install_chef_dk,
        null_resource.provision_chef_dk,
    ]

    provisioner "file" {
        content = <<-EOF

            HAS_CHEF_REPO=${ contains(keys(var.misc_repos), "chef") }

            if [ "$HAS_CHEF_REPO" = "true" ]; then
                CHEF_REPO_URL=${ contains(keys(var.misc_repos), "chef") ? lookup(var.misc_repos["chef"], "repo_url" ) : "" }
                CHEF_REPO_NAME=${ contains(keys(var.misc_repos), "chef") ? lookup(var.misc_repos["chef"], "repo_name" ) : "" }

                git clone $CHEF_REPO_URL /root/repos/$CHEF_REPO_NAME;
                (cd /root/repos/$CHEF_REPO_NAME && git checkout master && git fetch && git pull);

                for BOOK in `dir /root/repos/$CHEF_REPO_NAME/cookbooks`; do
                    berks install --berksfile /root/repos/$CHEF_REPO_NAME/cookbooks/$BOOK/Berksfile;
                    berks upload --berksfile /root/repos/$CHEF_REPO_NAME/cookbooks/$BOOK/Berksfile --force;
                done

                knife data bag create secrets
                knife data bag from file secrets /root/repos/$CHEF_REPO_NAME/data_bags/secrets

                for ROLE in `ls /root/repos/$CHEF_REPO_NAME/roles -p | grep -v /`; do
                    knife role from file /root/repos/$CHEF_REPO_NAME/roles/$ROLE;
                done
            else
                echo "Cannot proceed without chef repo"
                echo "Exiting"
                exit 1;
            fi

        EOF
        destination = "/tmp/upload_cookbooks.sh"
    }

    provisioner "remote-exec" {
        # Clone down the chef repo and `berks upload` the cookbooks to self
        inline = [
            "chmod +x /tmp/upload_cookbooks.sh",
            "/tmp/upload_cookbooks.sh",
        ]
    }

    connection {
        host = element(var.admin_public_ips, count.index)
        type = "ssh"
    }
}

resource "null_resource" "upload_chef_data_bags" {
    count = var.admin_servers
    depends_on = [
        module.admin_provisioners,
        null_resource.change_admin_hostname,
        null_resource.change_admin_dns,
        null_resource.install_gitlab,
        null_resource.restore_gitlab,
        null_resource.install_chef_server,
        null_resource.install_chef_dk,
        null_resource.provision_chef_dk,
        null_resource.upload_chef_cookbooks,
    ]

    provisioner "file" {
        content = <<-EOF

            HAS_PROXY_REPO=${ contains(keys(var.app_definitions), "proxy") }
            SERVICE_NAME=""

            if [ "$HAS_PROXY_REPO" = "true" ]; then
                GREEN_SERVICE_NAME=${ contains(keys(var.app_definitions), "proxy") ? lookup(var.app_definitions["proxy"], "green_service" ) : "" };
                BLUE_SERVICE_NAME=${ contains(keys(var.app_definitions), "proxy") ? lookup(var.app_definitions["proxy"], "blue_service" ) : "" };
                DEFAULT_SERVICE_COLOR=${ contains(keys(var.app_definitions), "proxy") ? lookup(var.app_definitions["proxy"], "default_active" ) : "" };
                SERVICE_NAME=$GREEN_SERVICE_NAME;

                if [ "$DEFAULT_SERVICE_COLOR" = "blue" ]; then
                    SERVICE_NAME=$BLUE_SERVICE_NAME;
                fi
            fi

            cat << EOJ > /tmp/pg.json
                {
                    "id": "pg",
                    "pass": "${var.pg_md5_password}"
                }
            EOJ
            knife data bag from file secrets /tmp/pg.json

            cat << EOJ > /tmp/docker_service.json
                {
                    "id": "docker_service",
                    "name": "$SERVICE_NAME"
                }
            EOJ
            knife data bag from file secrets /tmp/docker_service.json;

        EOF
        destination = "/tmp/upload_chef_data_bags.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/upload_chef_data_bags.sh",
            "/tmp/upload_chef_data_bags.sh",
        ]
    }

    connection {
        host = element(var.admin_public_ips, count.index)
        type = "ssh"
    }
}

resource "null_resource" "admin_bootstrap" {
    count = var.admin_servers
    depends_on = [
        module.admin_provisioners,
        null_resource.change_admin_hostname,
        null_resource.change_admin_dns,
        null_resource.install_gitlab,
        null_resource.restore_gitlab,
        null_resource.install_chef_server,
        null_resource.install_chef_dk,
        null_resource.provision_chef_dk,
        null_resource.upload_chef_cookbooks,
        null_resource.upload_chef_data_bags,
    ]

    provisioner "local-exec" {
        command = <<-EOF
            knife node delete ${element(var.admin_names, count.index)} --config ${var.chef_local_dir}/knife.rb -y;
            knife client delete ${element(var.admin_names, count.index)} --config ${var.chef_local_dir}/knife.rb -y;
            docker-machine ssh ${element(var.admin_names, count.index)} 'sudo rm /etc/chef/client.pem';
            exit 0;
        EOF
    }

    # TODO: This needs to be uploaded after cookbook upload but before
    # PG_PASSWORD is currently md5 hashed in chef. Need cookbook/databage to get password from consul
    # knife data bag from file secrets ~/code/chef/data_bags/secrets/pg.json
    provisioner "local-exec" {
        command = <<-EOF
            knife bootstrap ${element(var.admin_public_ips, count.index)} --sudo \
                --identity-file ~/.ssh/id_rsa --node-name ${element(var.admin_names, count.index)} \
                --run-list 'role[admin]' --config ${var.chef_local_dir}/knife.rb
        EOF
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
        null_resource.install_chef_server,
        null_resource.install_chef_dk,
        null_resource.provision_chef_dk,
        null_resource.upload_chef_cookbooks,
        null_resource.upload_chef_data_bags,
        null_resource.admin_bootstrap,
    ]

    provisioner "file" {
        content = <<-EOF
            check_docker() {
                LEADER_READY=$(consul kv get leader_ready);

                if [ "$LEADER_READY" = "true" ]; then
                    echo "Docker containers up";
                    exit 0;
                else
                    echo "Waiting 60 for docker containers";
                    sleep 60;
                    check_docker
                fi
            }

            check_consul() {
                chef-client;
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
        null_resource.install_chef_server,
        null_resource.install_chef_dk,
        null_resource.provision_chef_dk,
        null_resource.upload_chef_cookbooks,
        null_resource.upload_chef_data_bags,
        null_resource.admin_bootstrap,
        null_resource.change_proxy_dns,
        null_resource.sync_firewalls,
    ]

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
                PROXY_SERVICE_NAME=${ contains(keys(var.app_definitions), "proxy") ? lookup(var.app_definitions["proxy"], "service_name" ) : "" }
                PROXY_REPO_NAME=${ contains(keys(var.app_definitions), "proxy") ? lookup(var.app_definitions["proxy"], "repo_name" ) : "" }

                docker stack rm $PROXY_SERVICE_NAME
                sed -i 's/LISTEN_ON_SSL:\s\+"true"/LISTEN_ON_SSL:      "false"/g' $HOME/repos/$PROXY_REPO_NAME/docker-compose.yml
                docker stack deploy --compose-file $HOME/repos/$PROXY_REPO_NAME/docker-compose.yml $PROXY_SERVICE_NAME --with-registry-auth
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
            chef_repo = var.misc_repos["chef"]["repo_name"],
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
            "bash /root/code/scripts/letsencrypt.sh"
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
        null_resource.install_chef_server,
        null_resource.install_chef_dk,
        null_resource.provision_chef_dk,
        null_resource.upload_chef_cookbooks,
        null_resource.upload_chef_data_bags,
        null_resource.admin_bootstrap,
        null_resource.change_proxy_dns,
        null_resource.sync_firewalls,
        null_resource.setup_letsencrypt,
    ]

    provisioner "file" {
        content = <<-EOF
            HAS_PROXY_REPO=${ contains(keys(var.app_definitions), "proxy") }

            if [ "$HAS_PROXY_REPO" = "true" ]; then
                PROXY_SERVICE_NAME=${ contains(keys(var.app_definitions), "proxy") ? lookup(var.app_definitions["proxy"], "service_name" ) : "" }
                PROXY_REPO_NAME=${ contains(keys(var.app_definitions), "proxy") ? lookup(var.app_definitions["proxy"], "repo_name" ) : "" }

                docker stack rm $PROXY_SERVICE_NAME
                sed -i 's/LISTEN_ON_SSL:\s\+"false"/LISTEN_ON_SSL:      "true"/g' $HOME/repos/$PROXY_REPO_NAME/docker-compose.yml
                docker stack deploy --compose-file $HOME/repos/$PROXY_REPO_NAME/docker-compose.yml $PROXY_SERVICE_NAME --with-registry-auth
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

# TODO: Only backup if main server or dev backup with diff naming convention
resource "null_resource" "backup_server" {
    count = var.admin_servers
    depends_on = [
        null_resource.install_gitlab,
        null_resource.restore_gitlab,
    ]


    provisioner "file" {
        when = destroy
        content = file("${path.module}/template_files/backupGitlab.sh")
        destination = "/tmp/backupGitlab.sh"
    }

    provisioner "remote-exec" {
        when = destroy
        inline = [
            "chmod +x /tmp/backupGitlab.sh",
            (var.backup_gitlab
                ? "echo 0"
                : "sed -i 's/BACKUPS_ENABLED=true/BACKUPS_ENABLED=false/g' /tmp/backupGitlab.sh"),
            (var.backup_gitlab
                ? "cat /tmp/backupGitlab.sh"
                : "echo BACKUPS disabled"),
            (var.backup_gitlab
                ? "bash /tmp/backupGitlab.sh -r ${var.aws_bucket_region} -b ${var.aws_bucket_name}"
                : "echo 0"),
        ]
    }

    connection {
        host = element(var.admin_public_ips, count.index)
        type = "ssh"
    }
}
