
module "leader_provisioners" {
    source      = "../../provisioners"
    servers     = var.leader_servers
    names       = var.lead_names
    public_ips  = var.lead_public_ips
    private_ips = var.lead_private_ips
    region      = var.region

    aws_bot_access_key = var.aws_bot_access_key
    aws_bot_secret_key = var.aws_bot_secret_key

    deploy_key_location = var.deploy_key_location
    root_domain_name = var.root_domain_name
    misc_repos      = var.misc_repos
    chef_local_dir  = var.chef_local_dir
    chef_client_ver = var.chef_client_ver
    docker_compose_version = var.docker_compose_version
    docker_engine_install_url  = var.docker_engine_install_url
    consul_version         = var.consul_version

    join_machine_id = var.join_machine_id

    # consul_wan_leader_ip = var.aws_leaderIP
    consul_wan_leader_ip = var.external_leaderIP

    consul_lan_leader_ip = (length(var.admin_public_ips) > 0
        ? element(concat(var.admin_public_ips, [""]), var.admin_servers - 1)
        : element(concat(var.lead_public_ips, [""]), 0))

    datacenter_has_admin = length(var.admin_public_ips) > 0

    role = "manager"
    joinSwarm = true
    installCompose = true
    run_service_enabled = var.run_service_enabled
    send_jsons_enabled = var.send_jsons_enabled
    send_logs_enabled = var.send_logs_enabled

    # Variable to ensure the cookbooks are uploaded before bootstrapping
    chef_server_ready = local.chef_server_ready

    db_hostname_ready = local.db_hostname_ready
    admin_hostname_ready = local.admin_hostname_ready
    leader_hostname_ready = local.leader_hostname_ready
}


resource "null_resource" "change_leader_hostname" {
    count      = var.leader_servers

    provisioner "remote-exec" {
        inline = [
            "sudo hostnamectl set-hostname ${var.root_domain_name}",
            "sed -i 's/.*${var.server_name_prefix}-${var.region}.*/127.0.1.1 ${var.root_domain_name} ${element(var.lead_names, count.index)}/' /etc/hosts",
            "sed -i '$ a 127.0.1.1 ${var.root_domain_name} ${element(var.lead_names, count.index)}' /etc/hosts",
            "sed -i '$ a ${element(var.lead_public_ips, count.index)} ${var.root_domain_name} ${var.root_domain_name}' /etc/hosts",
            "cat /etc/hosts"
        ]
        connection {
            host = element(var.lead_public_ips, count.index)
            type = "ssh"
        }
    }
}

module "pull_docker_containers" {
    source = "../../provisioners/pull_containers"

    provisioners_done = module.leader_provisioners.end_of_provisioner
    servers = var.leader_servers
    public_ips = var.lead_public_ips
    app_definitions = var.app_definitions
    aws_ecr_region   = var.aws_ecr_region
}

resource "null_resource" "chef_client_initial_run" {
    count      = var.leader_servers > 0 ? 1 : 0
    depends_on = [null_resource.change_db_dns]

    triggers = {
        # TODO: Run this anytime we add a server - leader, web, db, etc
        #   Needs to be after the new server has been bootstrapped however, not sure what to do about that yet
        run_chef_client = var.leader_servers
    }

    provisioner "local-exec" {
        command = <<-EOF
            knife ssh 'role:*' 'chef-client' --identity-file ~/.ssh/id_rsa -x root -a ipaddress
            sleep 30
        EOF
    }
}

resource "null_resource" "sync_leader_with_admin_firewall" {
    count      = var.admin_servers
    depends_on = [null_resource.chef_client_initial_run]

    provisioner "file" {
        content = <<-EOF
            check_consul() {

                chef-client;
                consul kv put leader_bootstrapped true;

                ADMIN_READY=$(consul kv get admin_ready);

                if [ "$ADMIN_READY" = "true" ]; then
                    echo "Firewalls ready: Leader"
                    exit 0;
                else
                    echo "Waiting 60 for admin firewall";
                    sleep 60;
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

resource "null_resource" "start_docker_containers" {
    count      = var.leader_servers
    depends_on = [null_resource.sync_leader_with_admin_firewall]

    provisioner "remote-exec" {
        # We need to version this either in a seperate file or repo as something like
        # "default services/containers" for better transparency

        inline = [
            <<-EOF
                SLEEP_FOR=$((5 + $((${count.index} * 8)) ))
                echo "WAITING $SLEEP_FOR seconds"
                sleep $SLEEP_FOR

                NET_UP=$(docker network inspect proxy)
                if [ $? -eq 1 ]; then docker network create --attachable --driver overlay --subnet 192.168.0.0/16 proxy; fi

                ### NOTE: Once we move to blue/turquiose/green, we'll have to make
                ###  sure we bring up the correct service (_blue or _green, not _main)

                %{ for APP in var.app_definitions }

                    CHECK_SERVICE=${APP["green_service"]};
                    REPO_NAME=${APP["repo_name"]};
                    SERVICE_NAME=${APP["service_name"]};

                    APP_UP=$(docker service ps $CHECK_SERVICE)
                    [ -z "$APP_UP" ] && (cd /root/repos/$REPO_NAME && docker stack deploy --compose-file docker-compose.yml $SERVICE_NAME --with-registry-auth)

                %{ endfor }

                consul kv put leader_ready true;

                exit 0
            EOF
        ]
        connection {
            host = element(var.lead_public_ips, count.index)
            type = "ssh"
        }
    }
}

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
    depends_on = [null_resource.change_proxy_dns]

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

resource "null_resource" "install_runner" {
    count = var.leader_servers
    # depends_on = [null_resource.create_app_subdomains]
    depends_on = [null_resource.change_proxy_dns]

    provisioner "file" {
        content = <<-EOF

            HAS_SERVICE_REPO=${ contains(keys(var.misc_repos), "service") }

            curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo bash
            apt-cache madison gitlab-runner
            sudo apt-get install gitlab-runner jq -y
            sudo usermod -aG docker gitlab-runner

            if [ "$HAS_SERVICE_REPO" = "true" ]; then
                SERVICE_REPO_URL=${ contains(keys(var.misc_repos), "service") ? lookup(var.misc_repos["service"], "repo_url" ) : "" }
                SERVICE_REPO_NAME=${ contains(keys(var.misc_repos), "service") ? lookup(var.misc_repos["service"], "repo_name" ) : "" }
                git clone $SERVICE_REPO_URL /home/gitlab-runner/$SERVICE_REPO_NAME
            fi

            mkdir -p /home/gitlab-runner/.aws
            touch /home/gitlab-runner/.aws/credentials
            chown -R gitlab-runner:gitlab-runner /home/gitlab-runner
        EOF
        # chmod 0775 -R /home/gitlab-runner/$SERVICE_REPO_NAME
        destination = "/tmp/install_runner.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/install_runner.sh",
            "/tmp/install_runner.sh",
        ]
    }

    provisioner "file" {
        content = <<-EOF
            [default]
            aws_access_key_id = ${var.aws_bot_access_key}
            aws_secret_access_key = ${var.aws_bot_secret_key}
        EOF
        destination = "/home/gitlab-runner/.aws/credentials"
    }

    connection {
        host = element(var.lead_public_ips, 0)
        type = "ssh"
    }
}

##### NOTE: After obtaining the token we register the runner from the page
# TODO: Figure out a way to retrieve the token programmatically

# For a fresh project
# https://docs.gitlab.com/ee/api/projects.html#create-project
# For now this is overkill but we need to create the project, get its id, retrieve a private token
#   with api scope, make a curl request to get the project level runners_token and use that
# Programatically creating the project is a little tedious but honestly not a bad idea
#  considering we can then just push the code and images up if we didnt/dont have a backup

resource "null_resource" "register_runner" {
    # We can use count to actually say how many runners we want
    # Have a trigger set to update/destroy based on id etc
    # /etc/gitlab-runner/config.toml   set concurrent to number of runners
    # https://docs.gitlab.com/runner/configuration/advanced-configuration.html
    count = var.num_gitlab_runners
    depends_on = [null_resource.install_runner]

    # TODO: 1 or 2 prod runners with rest non-prod
    provisioner "remote-exec" {
        inline = [
            <<-EOF

                REGISTRATION_TOKEN=${var.gitlab_runner_tokens["service"]}
                echo $REGISTRATION_TOKEN


                if [ -z "$REGISTRATION_TOKEN" ]; then
                    echo "Obtain token and populate `service` key for `gitlab_runner_tokens` var in credentials.tf"
                    exit 1;
                fi

                sleep $((3 + $((${count.index} * 5)) ))

                sed -i "s|concurrent = 1|concurrent = 5|" /etc/gitlab-runner/config.toml

                sudo gitlab-runner register -n \
                  --url "https://gitlab.${var.root_domain_name}" \
                  --registration-token "$REGISTRATION_TOKEN" \
                  --executor shell \
                  --run-untagged="true" \
                  --locked="false" \
                  --description "Shell Runner"

                  sleep $((2 + $((${count.index} * 5)) ))

                  # https://gitlab.com/gitlab-org/gitlab-runner/issues/1316
                  gitlab-runner verify --delete
            EOF
        ]
        # sudo gitlab-runner register \
        #     --non-interactive \
        #     --url "https://gitlab.${var.root_domain_name}" \
        #     --registration-token "${REGISTRATION_TOKEN}" \
        #     --description "docker-runner" \
        #     --tag-list "docker" \
        #     --run-untagged="true" \
        #     --locked="false" \
        #     --executor "docker" \
        #     --docker-image "docker:19.03.1" \
        #     --docker-privileged \
        #     --docker-volumes "/certs/client"
    }
    connection {
        host = element(var.lead_public_ips, 0)
        type = "ssh"
    }
}
