### NOTE: The goal is to turn these into "roles" that can all be applied to the
###   same server and also multiple servers to scale
###  IE, In one env, it has 1 server that does all: leader, admin, and db
###  Another can have 1 server as admin and leader with seperate db server
###  Another can have 1 server with all roles and scale out aditional servers as leader servers
###  Simplicity/Flexibility/Adaptability

#module "ansible" {
#    source = "../ansible"
#}
resource "null_resource" "ansible_hosts" {
    count = 1
    triggers = {
        ips = join(",", local.all_public_ips)
        hostfile = var.ansible_hostfile
    }

    provisioner "local-exec" {
        command = <<-EOF
		cat <<-EOLF > ${var.ansible_hostfile}
		[servers]
		%{ for ind, HOST in var.ansible_hosts ~}
		${HOST.name} ansible_host=${HOST.ip}
		%{ endfor ~}
		
		%{ if length(var.admin_public_ips) > 0 ~}
		[admin]
		%{ for ind, HOST in var.ansible_hosts ~}
		%{ if contains(HOST.roles, "admin") ~}
		${HOST.name}_admin ansible_host=${HOST.ip}
		%{ endif ~}
		%{ endfor ~}
		%{ endif ~}
		
		%{ if length(var.lead_public_ips) > 0 ~}
		[lead]
		%{ for ind, HOST in var.ansible_hosts ~}
		%{ if contains(HOST.roles, "lead") ~}
		${HOST.name}_lead ansible_host=${HOST.ip}
		%{ endif ~}
		%{ endfor ~}
		%{ endif ~}
		
		%{ if length(var.db_public_ips) > 0 ~}
		[db]
		%{ for ind, HOST in var.ansible_hosts ~}
		%{ if contains(HOST.roles, "db") ~}
		${HOST.name}_db ansible_host=${HOST.ip}
		%{ endif ~}
		%{ endfor ~}
		%{ endif ~}
		
		%{ if length(var.build_public_ips) > 0 ~}
		[build]
		%{ for ind, HOST in var.ansible_hosts ~}
		%{ if contains(HOST.roles, "build") ~}
		${HOST.name}_build ansible_host=${HOST.ip}
		%{ endif ~}
		%{ endfor ~}
		%{ endif ~}
		
		[all:vars]
		ansible_python_interpreter=/usr/bin/python3
		EOLF
        EOF
    }
    provisioner "local-exec" {
        when = destroy
        command = "rm ./${self.triggers.hostfile}"
        on_failure = continue
    }
}


module "swarm" {
    source = "../swarm"

    lead_servers = local.lead_servers
    lead_public_ips  = var.lead_public_ips
    lead_names       = var.lead_names
    region      = var.region
}

module "gpg" {
    source = "../gpg"
    count = var.use_gpg ? 1 : 0
    depends_on = [module.swarm]

    s3alias = var.s3alias
    s3bucket = var.s3bucket

    bot_gpg_name = var.bot_gpg_name
    bot_gpg_passphrase = var.bot_gpg_passphrase

    admin_public_ips = var.admin_public_ips
    db_public_ips = var.db_public_ips

    admin_servers = local.admin_servers
    is_only_db_count = local.is_only_db_count

}

### NOTE: Only thing for this is consul needs to be installed
resource "null_resource" "add_proxy_hosts" {
    count      = 1
    depends_on = [
        module.gpg
    ]

    #### TODO: Find a way to gradually migrate from blue -> green and vice versa vs
    ####   just sending all req suddenly from blue to green
    #### This way if the deployment was scuffed, it only affects X% of users whether
    ####   pre-determined  20/80 split etc. or part of slow rollout
    #### TODO: We already register a check/service with consul.. maybe have the app also
    ####   register its consul endpoints as well?

    triggers = {
        num_apps = length(keys(var.app_definitions))
        additional_ssl = join(",", [
            for app in var.additional_ssl:
            app.service_name
            if app.create_ssl_cert == true
        ])
    }

    provisioner "file" {
        content = <<-EOF
            
            consul kv delete -recurse applist

            %{ for APP in var.app_definitions }

                SUBDOMAIN_NAME=${APP["subdomain_name"]};
                SERVICE_NAME=${APP["service_name"]};
                GREEN_SERVICE=${APP["green_service"]};
                BLUE_SERVICE=${APP["blue_service"]};
                DEFAULT_ACTIVE=${APP["default_active"]};

                consul kv put apps/$SUBDOMAIN_NAME/green $GREEN_SERVICE
                consul kv put apps/$SUBDOMAIN_NAME/blue $BLUE_SERVICE
                consul kv put apps/$SUBDOMAIN_NAME/active $DEFAULT_ACTIVE
                consul kv put applist/$SERVICE_NAME $SUBDOMAIN_NAME

            %{ endfor }

            %{ for APP in var.additional_ssl }

                SUBDOMAIN_NAME=${APP["subdomain_name"]};
                SERVICE_NAME=${APP["service_name"]};

                consul kv put applist/$SERVICE_NAME $SUBDOMAIN_NAME

                ### This is temporary
                consul kv put apps/$SUBDOMAIN_NAME/green 172.17.0.1:31000
                consul kv put apps/$SUBDOMAIN_NAME/blue _dev
                consul kv put apps/$SUBDOMAIN_NAME/active green

                consul kv put apps/$SUBDOMAIN_NAME.beta/green 172.17.0.1:31000
                consul kv put apps/$SUBDOMAIN_NAME.beta/blue _dev
                consul kv put apps/$SUBDOMAIN_NAME.beta/active green
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
        host = element(concat(var.admin_public_ips, var.lead_public_ips), 0)
        type = "ssh"
    }
}

resource "null_resource" "prometheus_targets" {
    count = local.admin_servers
    depends_on = [
        null_resource.add_proxy_hosts,
    ]

    triggers = {
        ips = join(",", local.all_private_ips)
    }

    ## 9107 is consul exporter
    provisioner "file" {
            #{
            #    "targets": ["localhost:9107"]
            #}
        content = <<-EOF
        [
        %{ for ind, IP in local.all_private_ips }
            {
                "targets": ["${length(regexall("admin", local.all_names[ind])) > 0 ? "localhost" : IP}:9100"],
                "labels": {
                    "hostname": "${length(regexall("admin", local.all_names[ind])) > 0 ? "gitlab.${var.root_domain_name}" : local.all_names[ind]}",
                    "public_ip": "${local.all_public_ips[ind]}",
                    "private_ip": "${IP}",
                    "nodename": "${local.all_names[ind]}"
                }
            }${ind < length(local.all_private_ips) - 1 ? "," : ""}
        %{ endfor }
        ]
        EOF
        destination = "/tmp/targets.json"
    }

    provisioner "file" {
        content = <<-EOF
        {
            "service": {
                "name": "consulexporter",
                "port": 9107
            }
        }
        EOF
        destination = "/etc/consul.d/conf.d/consulexporter.json"
    }

    provisioner "remote-exec" {
        inline = [ "consul reload" ]
    }

    connection {
        host = element(var.admin_public_ips, 0)
        type = "ssh"
    }
}


### NOTE: GITLAB MEMORY
###  https://techoverflow.net/2020/04/18/how-i-reduced-gitlab-memory-consumption-in-my-docker-based-setup/
###  https://docs.gitlab.com/omnibus/settings/memory_constrained_envs.html
resource "null_resource" "install_gitlab" {
    count = local.admin_servers
    depends_on = [ null_resource.add_proxy_hosts ]

    # # After renewing certs possibly
    # sudo gitlab-ctl hup nginx

    # sudo mkdir -p /etc/gitlab/ssl/${var.root_domain_name};
    # sudo chmod 600 /etc/gitlab/ssl/${var.root_domain_name};

    ### Streamlined in 13.9
    ### sudo gitlab-rake "gitlab:password:reset[root]"
    # Ruby helper cmd: Reset Password
    # gitlab-rails console -e production
    # user = User.where(id: 1).first
    # user.password = 'mytemp'
    # user.password_confirmation = 'secret_pass'
    # user.save!

    ###! Mattermost defaults
    ###! /var/opt/gitlab/mattermost   mattermost dir
    ###! /var/opt/gitlab/mattermost/config.json   for server settings
    ###! /var/opt/gitlab/mattermost/*plugins      for plugins
    ###! /var/opt/gitlab/mattermost/data          for server data

    ###! Grafana data located at /var/opt/gitlab/grafana/data/
    ###! Loaded prometheus config at /var/opt/gitlab/prometheus/prometheus.yml managed by gitlab.rb

    provisioner "remote-exec" {
        inline = [
            <<-EOF
                sudo gitlab-ctl restart
                sed -i "s|external_url 'http://[0-9a-zA-Z.-]*'|external_url 'https://gitlab.${var.root_domain_name}'|" /etc/gitlab/gitlab.rb
                sed -i "s|https://registry.example.com|https://registry.${var.root_domain_name}|" /etc/gitlab/gitlab.rb
                sed -i "s|# registry_external_url|registry_external_url|" /etc/gitlab/gitlab.rb
                sed -i "s|# letsencrypt\['enable'\] = nil|letsencrypt\['enable'\] = true|" /etc/gitlab/gitlab.rb
                sed -i "s|# letsencrypt\['contact_emails'\] = \[\]|letsencrypt\['contact_emails'\] = \['${var.contact_email}'\]|" /etc/gitlab/gitlab.rb
                sed -i "s|# letsencrypt\['auto_renew'\]|letsencrypt\['auto_renew'\]|" /etc/gitlab/gitlab.rb
                sed -i "s|# letsencrypt\['auto_renew_hour'\]|letsencrypt\['auto_renew_hour'\]|" /etc/gitlab/gitlab.rb
                sed -i "s|# letsencrypt\['auto_renew_minute'\] = nil|letsencrypt\['auto_renew_minute'\] = 30|" /etc/gitlab/gitlab.rb
                sed -i "s|# letsencrypt\['auto_renew_day_of_month'\]|letsencrypt\['auto_renew_day_of_month'\]|" /etc/gitlab/gitlab.rb
                sed -i "s|# nginx\['custom_nginx_config'\]|nginx\['custom_nginx_config'\]|" /etc/gitlab/gitlab.rb
                sed -i "s|\"include /etc/nginx/conf\.d/example\.conf;\"|\"include /etc/nginx/conf\.d/\*\.conf;\"|" /etc/gitlab/gitlab.rb

                CONFIG="prometheus['scrape_configs'] = [
                    {
                        'job_name': 'node-file',
                        'honor_labels': true,
                        'file_sd_configs' => [
                            'files' => ['/tmp/targets.json']
                        ],
                    },
                    {
                        'job_name': 'consul-exporter',
                        'honor_labels': true,
                        'consul_sd_configs' => [
                            'server': 'localhost:8500',
                            'services' => ['consulexporter']
                        ]
                    }
                ]"
                printf '%s\n' "/# prometheus\['scrape_configs'\]" ".,+7c" "$CONFIG" . wq | ed -s /etc/gitlab/gitlab.rb


                sleep 5;
                sudo gitlab-ctl reconfigure

                sed -i "s|# mattermost_external_url 'https://[0-9a-zA-Z.-]*'|mattermost_external_url 'https://${var.mattermost_subdomain}.${var.root_domain_name}'|" /etc/gitlab/gitlab.rb;
                echo "alias mattermost-cli=\"cd /opt/gitlab/embedded/service/mattermost && sudo /opt/gitlab/embedded/bin/chpst -e /opt/gitlab/etc/mattermost/env -P -U mattermost:mattermost -u mattermost:mattermost /opt/gitlab/embedded/bin/mattermost --config=/var/opt/gitlab/mattermost/config.json $1\"" >> ~/.bashrc

                sleep 5;
                sudo gitlab-ctl reconfigure;
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
    count = local.admin_servers
    depends_on = [
        null_resource.add_proxy_hosts,
        null_resource.install_gitlab,
    ]

    # NOTE: Sleep is for internal api, takes a second after a restore
    # Otherwise git clones and docker pulls won't work in the next step
    # TODO: Hardcoded repo and SNIPPET_ID/filename for remote mirrors file
    provisioner "remote-exec" {
        inline = [
            <<-EOF
                chmod +x /root/code/scripts/misc/importGitlab.sh;

                TERRA_WORKSPACE=${terraform.workspace}
                IMPORT_GITLAB=${var.import_gitlab}
                PASSPHRASE_FILE="${var.use_gpg ? "-p $HOME/${var.bot_gpg_name}" : "" }"
                if [ ! -z "${var.import_gitlab_version}" ]; then IMPORT_GITLAB_VERSION="-v ${var.import_gitlab_version}"; fi

                if [ "$IMPORT_GITLAB" = "true" ]; then
                    bash /root/code/scripts/misc/importGitlab.sh -a ${var.s3alias} -b ${var.s3bucket} $PASSPHRASE_FILE $IMPORT_GITLAB_VERSION;
                    echo "=== Wait 90s for restore ==="
                    sleep 90

                    if [ "$TERRA_WORKSPACE" != "default" ]; then
                        echo "WORKSPACE: $TERRA_WORKSPACE, removing remote mirrors"
                        SNIPPET_ID=34
                        FILENAME="PROJECTS.txt"
                        LOCAL_PROJECT_FILE="/tmp/$FILENAME"
                        LOCAL_MIRROR_FILE="/tmp/MIRRORS.txt"

                        ## Get list of projects with remote mirrors
                        curl -sL "https://gitlab.${var.root_domain_name}/os/workbench/-/snippets/$SNIPPET_ID/raw/main/$FILENAME" -o $LOCAL_PROJECT_FILE

                        ## Create token to modify all projects
                        TERRA_UUID=${uuid()}
                        sudo gitlab-rails runner "token = User.find(1).personal_access_tokens.create(scopes: [:api], name: 'Temp PAT'); token.set_token('$TERRA_UUID'); token.save!";

                        ## Iterate through project ids
                        while read PROJECT_ID; do
                            ## Get list of projects remote mirror ids
                            ##  https://docs.gitlab.com/ee/api/remote_mirrors.html#list-a-projects-remote-mirrors
                            curl -s -H "PRIVATE-TOKEN: $TERRA_UUID" "https://gitlab.${var.root_domain_name}/api/v4/projects/$PROJECT_ID/remote_mirrors" | jq ".[].id" > $LOCAL_MIRROR_FILE

                            ## Iterate through remote mirror ids per project
                            while read MIRROR_ID; do
                                ## Update each remote mirror attribute --enabled=false
                                ##  https://docs.gitlab.com/ee/api/remote_mirrors.html#update-a-remote-mirrors-attributes
                                curl -X PUT --data "enabled=false" -H "PRIVATE-TOKEN: $TERRA_UUID" "https://gitlab.${var.root_domain_name}/api/v4/projects/$PROJECT_ID/remote_mirrors/$MIRROR_ID"
                                sleep 1;
                            done <$LOCAL_MIRROR_FILE

                        done <$LOCAL_PROJECT_FILE

                        ## Revoke token
                        sudo gitlab-rails runner "PersonalAccessToken.find_by_token('$TERRA_UUID').revoke!";
                    fi

                fi

                exit 0;
            EOF
        ]

        connection {
            host = element(var.admin_public_ips, 0)
            type = "ssh"
        }
    }

    # Change known_hosts to new imported ssh keys from gitlab restore
    provisioner "local-exec" {
        command = <<-EOF
            ssh-keygen -f ~/.ssh/known_hosts -R ${element(var.admin_public_ips, 0)}
            ssh-keyscan -H ${element(var.admin_public_ips, 0)} >> ~/.ssh/known_hosts
        EOF
    }
}

resource "null_resource" "gitlab_plugins" {
    count = local.admin_servers
    depends_on = [
        null_resource.add_proxy_hosts,
        null_resource.install_gitlab,
        null_resource.restore_gitlab,
    ]

    ###! TODO: Conditionally deal with plugins if the subdomains are present etc.
    ###! ex: User does not want mattermost or wekan

    ###! TODO: Would be nice if unauthenticated users could view certain channels in mattermost
    ###! Might be possible if we can create a custom role?
    ###!   https://docs.mattermost.com/onboard/advanced-permissions-backend-infrastructure.html

    ###! TODO: If we run plugins, then run import again, plugins are messed up
    ###!  We also need to be able to correctly sed replace grafana (its not rerunnable atm)
    provisioner "remote-exec" {
        inline = [
            <<-EOF
                PLUGIN1_NAME="WekanPlugin";
                PLUGIN2_NAME="MattermostPlugin";
                PLUGIN3_NAME="GrafanaPlugin";
                PLUGIN3_INIT_NAME="GitLab Grafana";
                TERRA_UUID=${uuid()}
                echo $TERRA_UUID;

                ## To initially access grafana as admin, must enable login using user/pass
                ## https://docs.gitlab.com/omnibus/settings/grafana.html#enable-login-using-username-and-password
                ## grafana['disable_login_form'] = false

                ## Also MUST change admin password using: `gitlab-ctl set-grafana-password`
                ## Modifying "grafana['admin_password'] = 'foobar'" will NOT work (multiple reconfigures have occured)
                ## https://docs.gitlab.com/omnibus/settings/grafana.html#resetting-the-admin-password

                echo "=== Wait 90s for gitlab api for oauth plugins ==="
                sleep 90;

                sudo gitlab-rails runner "token = User.find(1).personal_access_tokens.create(scopes: [:api], name: 'Temp PAT'); token.set_token('$TERRA_UUID'); token.save!";

                PLUGIN1_ID=$(curl --header "PRIVATE-TOKEN: $TERRA_UUID" "https://gitlab.${var.root_domain_name}/api/v4/applications" | jq ".[] | select(.application_name | contains (\"$PLUGIN1_NAME\")) | .id");
                curl --request DELETE --header "PRIVATE-TOKEN: $TERRA_UUID" "https://gitlab.${var.root_domain_name}/api/v4/applications/$PLUGIN1_ID";

                sleep 5;
                OAUTH=$(curl --request POST --header "PRIVATE-TOKEN: $TERRA_UUID" \
                    --data "name=$PLUGIN1_NAME&redirect_uri=https://${var.wekan_subdomain}.${var.root_domain_name}/_oauth/oidc&scopes=openid%20profile%20email" \
                    "https://gitlab.${var.root_domain_name}/api/v4/applications");

                APP_ID=$(echo $OAUTH | jq -r ".application_id");
                APP_SECRET=$(echo $OAUTH | jq -r ".secret");

                consul kv put wekan/app_id $APP_ID
                consul kv put wekan/secret $APP_SECRET



                FOUND_CORRECT_ID2=$(curl --header "PRIVATE-TOKEN: $TERRA_UUID" "https://gitlab.${var.root_domain_name}/api/v4/applications" | jq ".[] | select(.application_name | contains (\"$PLUGIN2_NAME\")) | select(.callback_url | contains (\"${var.root_domain_name}\")) | .id");

                if [ -z "$FOUND_CORRECT_ID2" ]; then
                    PLUGIN2_ID=$(curl --header "PRIVATE-TOKEN: $TERRA_UUID" "https://gitlab.${var.root_domain_name}/api/v4/applications" | jq ".[] | select(.application_name | contains (\"$PLUGIN2_NAME\")) | .id");
                    curl --request DELETE --header "PRIVATE-TOKEN: $TERRA_UUID" "https://gitlab.${var.root_domain_name}/api/v4/applications/$PLUGIN2_ID";

                    OAUTH2=$(curl --request POST --header "PRIVATE-TOKEN: $TERRA_UUID" \
                        --data "name=$PLUGIN2_NAME&redirect_uri=https://${var.mattermost_subdomain}.${var.root_domain_name}/plugins/com.github.manland.mattermost-plugin-gitlab/oauth/complete&scopes=api%20read_user" \
                        "https://gitlab.${var.root_domain_name}/api/v4/applications");

                    APP_ID2=$(echo $OAUTH2 | jq -r ".application_id");
                    APP_SECRET2=$(echo $OAUTH2 | jq -r ".secret");

                    sed -i "s|\"gitlaburl\": \"https://[0-9a-zA-Z.-]*\"|\"gitlaburl\": \"https://gitlab.${var.root_domain_name}\"|" /var/opt/gitlab/mattermost/config.json
                    sed -i "s|\"gitlaboauthclientid\": \"[0-9a-zA-Z.-]*\"|\"gitlaboauthclientid\": \"$APP_ID2\"|" /var/opt/gitlab/mattermost/config.json
                    sed -i "s|\"gitlaboauthclientsecret\": \"[0-9a-zA-Z.-]*\"|\"gitlaboauthclientsecret\": \"$APP_SECRET2\"|" /var/opt/gitlab/mattermost/config.json

                    sudo gitlab-ctl restart mattermost;
                fi

                FOUND_CORRECT_ID3=$(curl --header "PRIVATE-TOKEN: $TERRA_UUID" "https://gitlab.${var.root_domain_name}/api/v4/applications" | jq ".[] | select(.application_name | contains (\"$PLUGIN3_INIT_NAME\")) | select(.callback_url | contains (\"${var.root_domain_name}\")) | .id");

                ## If we dont find "GitLab Grafana" (initial grafana oauth app), we have to update /etc/gitlab/gitlab.rb every time with our own
                ## Wish there was a way to revert to the original oauth version after deleting it but not sure how
                if [ -z "$FOUND_CORRECT_ID3" ]; then
                    PLUGIN3_ID=$(curl --header "PRIVATE-TOKEN: $TERRA_UUID" "https://gitlab.${var.root_domain_name}/api/v4/applications" | jq ".[] | select(.application_name | contains (\"$PLUGIN3_NAME\")) | .id");
                    curl --request DELETE --header "PRIVATE-TOKEN: $TERRA_UUID" "https://gitlab.${var.root_domain_name}/api/v4/applications/$PLUGIN3_ID";

                    OAUTH3=$(curl --request POST --header "PRIVATE-TOKEN: $TERRA_UUID" \
                        --data "name=$PLUGIN3_NAME&redirect_uri=https://gitlab.${var.root_domain_name}/-/grafana/login/gitlab&scopes=read_user" \
                        "https://gitlab.${var.root_domain_name}/api/v4/applications");

                    APP_ID3=$(echo $OAUTH3 | jq -r ".application_id");
                    APP_SECRET3=$(echo $OAUTH3 | jq -r ".secret");

                    sed -i "s|# grafana\['gitlab_application_id'\] = 'GITLAB_APPLICATION_ID'|grafana\['gitlab_application_id'\] = '$APP_ID3'|" /etc/gitlab/gitlab.rb
                    sed -i "s|# grafana\['gitlab_secret'\] = 'GITLAB_SECRET'|grafana\['gitlab_secret'\] = '$APP_SECRET3'|" /etc/gitlab/gitlab.rb

                    sudo gitlab-ctl reconfigure;
                fi

                ### Some good default admin settings
                OUTBOUND_ARR="chat.${var.root_domain_name},10.0.0.0%2F8"
                curl --request PUT --header "PRIVATE-TOKEN: $TERRA_UUID" \
                    "https://gitlab.${var.root_domain_name}/api/v4/application/settings?signup_enabled=false&usage_ping_enabled=false&outbound_local_requests_allowlist_raw=$OUTBOUND_ARR"


                sleep 3;
                sudo gitlab-rails runner "PersonalAccessToken.find_by_token('$TERRA_UUID').revoke!";

            EOF
        ]
    }

    connection {
        host = element(var.admin_public_ips, 0)
        type = "ssh"
    }
}

# NOTE: Used to re-authenticate mattermost with gitlab
resource "null_resource" "reauthorize_mattermost" {
    count = 0
    depends_on = [
        null_resource.add_proxy_hosts,
        null_resource.install_gitlab,
        null_resource.restore_gitlab,
    ]

    provisioner "remote-exec" {
        ###! Below is necessary for re-authenticating mattermost with gitlab (if initial auth doesnt work)
        ###! Problem is the $'' style syntax used to preserve \n doesnt like terraform variable expression
        inline = [
            <<-EOF

                PLUGIN_NAME="Gitlab Mattermost";
                TERRA_UUID=${uuid()}
                echo $TERRA_UUID;

                sudo gitlab-rails runner "token = User.find(1).personal_access_tokens.create(scopes: [:api], name: 'Temp PAT'); token.set_token('$TERRA_UUID'); token.save!"

                OAUTH=$(curl --request POST --header "PRIVATE-TOKEN: $TERRA_UUID" \
                    --data $'name=$PLUGIN_NAME&redirect_uri=https://${var.mattermost_subdomain}.${var.root_domain_name}/signup/gitlab/complete\nhttps://${var.mattermost_subdomain}.${var.root_domain_name}/login/gitlab/complete&scopes=' \
                    "https://gitlab.${var.root_domain_name}/api/v4/applications");

                APP_ID=$(echo $OAUTH | jq ".application_id");
                APP_SECRET=$(echo $OAUTH | jq ".secret");

                sed -i "s|# mattermost\['enable'\] = false|mattermost\['enable'\] = true|" /etc/gitlab/gitlab.rb;
                sed -i "s|# mattermost\['gitlab_enable'\] = false|mattermost\['gitlab_enable'\] = true|" /etc/gitlab/gitlab.rb;
                sed -i "s|# mattermost\['gitlab_id'\] = \"12345656\"|mattermost\['gitlab_id'\] = $APP_ID|" /etc/gitlab/gitlab.rb;
                sed -i "s|# mattermost\['gitlab_secret'\] = \"123456789\"|mattermost\['gitlab_secret'\] = $APP_SECRET|" /etc/gitlab/gitlab.rb;
                sed -i "s|# mattermost\['gitlab_scope'\] = \"\"|mattermost\['gitlab_scope'\] = \"\"|" /etc/gitlab/gitlab.rb;
                sed -i "s|# mattermost\['gitlab_auth_endpoint'\] = \"http://gitlab.example.com/oauth/authorize\"|mattermost\['gitlab_auth_endpoint'\] = \"https://gitlab.${var.root_domain_name}/oauth/authorize\"|" /etc/gitlab/gitlab.rb
                sed -i "s|# mattermost\['gitlab_token_endpoint'\] = \"http://gitlab.example.com/oauth/token\"|mattermost\['gitlab_token_endpoint'\] = \"https://gitlab.${var.root_domain_name}/oauth/token\"|" /etc/gitlab/gitlab.rb
                sed -i "s|# mattermost\['gitlab_user_api_endpoint'\] = \"http://gitlab.example.com/api/v4/user\"|mattermost\['gitlab_user_api_endpoint'\] = \"https://gitlab.${var.root_domain_name}/api/v4/user\"|" /etc/gitlab/gitlab.rb

                sudo gitlab-rails runner "PersonalAccessToken.find_by_token('$TERRA_UUID').revoke!"

            EOF
        ]
    }

    connection {
        host = element(var.admin_public_ips, 0)
        type = "ssh"
    }
}


resource "null_resource" "node_exporter" {
    count = local.admin_servers > 0 ? local.server_count : 0
    depends_on = [
        null_resource.add_proxy_hosts,
        null_resource.install_gitlab,
        null_resource.restore_gitlab
    ]

    #TODO: pass node_exporter version
    #TODO: pass consul_exporter version
    #TODO: pass promtail version
    provisioner "remote-exec" {
        inline = [
            "FILENAME1=node_exporter-1.2.0.linux-amd64.tar.gz",
            "[ ! -f /tmp/$FILENAME1 ] && wget https://github.com/prometheus/node_exporter/releases/download/v1.2.0/$FILENAME1 -P /tmp",
            "tar xvfz /tmp/$FILENAME1 --wildcards --strip-components=1 -C /usr/local/bin */node_exporter",
            "FILENAME2=promtail-linux-amd64.zip",
            "[ ! -f /tmp/$FILENAME2 ] && wget https://github.com/grafana/loki/releases/download/v2.2.1/$FILENAME2 -P /tmp",
            "unzip /tmp/$FILENAME2 -d /usr/local/bin && chmod a+x /usr/local/bin/promtail*amd64",
            "FILENAME3=promtail-local-config.yaml",
            "mkdir -p /etc/promtail.d",
            "[ ! -f /etc/promtail.d/$FILENAME3 ] && wget https://raw.githubusercontent.com/grafana/loki/main/clients/cmd/promtail/$FILENAME3 -P /etc/promtail.d",
            "sed -i \"s/localhost:/${var.admin_private_ips[0]}:/\" /etc/promtail.d/$FILENAME3",
            "sed -ni '/nodename:/!p; $ a \\      nodename: ${local.all_names[count.index]}' /etc/promtail.d/$FILENAME3",
            "FILENAME4=consul_exporter-0.7.1.linux-amd64.tar.gz",
            "[ ! -f /tmp/$FILENAME4 ] && wget https://github.com/prometheus/consul_exporter/releases/download/v0.7.1/$FILENAME4 -P /tmp",
            "tar xvfz /tmp/$FILENAME4 --wildcards --strip-components=1 -C /usr/local/bin */consul_exporter",
        ]
    }

    #Temp?
    ##TODO: Probably best in provision module
    provisioner "file" {
        content = templatefile("${path.module}/templates/nodeexporter.service", {})
        destination = "/etc/systemd/system/nodeexporter.service"
    }
    #Temp?
    provisioner "file" {
        content = templatefile("${path.module}/templates/consulexporter.service", {})
        destination = "/etc/systemd/system/consulexporter.service"
    }
    #Temp?
    provisioner "file" {
        content = templatefile("${path.module}/templates/promtail.service", {})
        destination = "/etc/systemd/system/promtail.service"
    }

    provisioner "remote-exec" {
        inline = [
            length(regexall("admin", local.all_names[count.index])) > 0 ? "echo 0" : "sudo systemctl start nodeexporter",
            length(regexall("admin", local.all_names[count.index])) > 0 ? "echo 0" : "sudo systemctl enable nodeexporter",
            length(regexall("admin", local.all_names[count.index])) > 0 ? "sudo systemctl start consulexporter" : "echo 0",
            length(regexall("admin", local.all_names[count.index])) > 0 ? "sudo systemctl enable consulexporter" : "echo 0",
            "sudo systemctl start promtail",
            "sudo systemctl enable promtail",
        ]
    }

    connection {
        host = element(local.all_public_ips, count.index)
        type = "ssh"
    }
}

#TODO: pass Loki version
resource "null_resource" "install_loki" {
    count = local.admin_servers
    depends_on = [
        null_resource.add_proxy_hosts,
        null_resource.install_gitlab,
        null_resource.restore_gitlab
    ]

    provisioner "file" {
        content = templatefile("${path.module}/templates/loki.service", {})
        destination = "/etc/systemd/system/loki.service"
    }

    provisioner "file" {
        content = <<-EOF
            ARCH=$(dpkg --print-architecture)
            LOKI_VERSION=2.2.1
            LOKI_LOCATION="/etc/loki.d"
            LOKI_USER="root"
            FILENAME="loki-linux-$ARCH"
            sudo mkdir -p $LOKI_LOCATION
            sudo chown -R $LOKI_USER:$LOKI_USER $LOKI_LOCATION
            curl -L https://github.com/grafana/loki/releases/download/v$LOKI_VERSION/$FILENAME.zip -o /tmp/$FILENAME.zip
            unzip /tmp/$FILENAME.zip -d $LOKI_LOCATION/
            wget https://raw.githubusercontent.com/grafana/loki/v$LOKI_VERSION/cmd/loki/loki-local-config.yaml -P $LOKI_LOCATION
            rm -rf /tmp/$FILENAME.zip
            sudo mv $LOKI_LOCATION/$FILENAME /usr/local/bin/loki
            sudo systemctl daemon-reload
            sudo systemctl start loki.service
            sudo systemctl enable loki.service
        EOF
        destination = "/tmp/install_loki.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/install_loki.sh",
            "/tmp/install_loki.sh"
        ]
    }

    connection {
        host = element(var.admin_public_ips, count.index)
        type = "ssh"
    }
}

module "admin_nginx" {
    count = local.lead_servers > 0 ? local.admin_servers : 0
    source = "../nginx"
    depends_on = [
        null_resource.add_proxy_hosts,
        null_resource.install_gitlab,
        null_resource.restore_gitlab
    ]

    admin_servers = local.admin_servers
    admin_public_ips = var.admin_public_ips

    root_domain_name = var.root_domain_name
    app_definitions = var.app_definitions
    additional_domains = var.additional_domains
    additional_ssl = var.additional_ssl

    lead_public_ips = var.lead_public_ips
    ## Technically just need to send proxy ip here instead of all private leader ips
    lead_private_ips = var.lead_private_ips

    https_port = "4433"
    cert_port = "7080" ## Currently hardcoded in letsencrypt/letsencrypt.tmpl

}



resource "null_resource" "install_dbs" {
    count      = local.db_servers > 0 ? local.db_servers : 0
    depends_on = [
        null_resource.add_proxy_hosts,
        null_resource.install_gitlab,
        null_resource.restore_gitlab
    ]

    provisioner "remote-exec" {
        # TODO: Setup to bind to private net/vpc instead of relying soley on the security group/firewall for all dbs
        inline = [
            "chmod +x /root/code/scripts/install/install_redis.sh",
            "chmod +x /root/code/scripts/install/install_mongo.sh",
            "chmod +x /root/code/scripts/install/install_pg.sh",
            (length(var.redis_dbs) > 0 ? "sudo service redis_6379 start;" : "echo 0;"),
            (length(var.redis_dbs) > 0 ? "sudo systemctl enable redis_6379" : "echo 0;"),
            (length(var.mongo_dbs) > 0
                ? "bash /root/code/scripts/install/install_mongo.sh -v 4.4.6 -i ${element(var.db_private_ips, count.index)};"
                : "echo 0;"),
            (length(var.pg_dbs) > 0
                ? "bash /root/code/scripts/install/install_pg.sh -v 9.5;"
                : "echo 0;"),
            "exit 0;"
        ]
    }
    connection {
        host = element(var.db_public_ips, count.index)
        type = "ssh"
    }
}

resource "null_resource" "import_dbs" {
    count = var.import_dbs && local.db_servers > 0 ? length(var.dbs_to_import) : 0
    depends_on = [
        null_resource.add_proxy_hosts,
        null_resource.install_gitlab,
        null_resource.restore_gitlab,
        null_resource.install_dbs
    ]

    provisioner "file" {
        content = <<-EOF
            IMPORT=${var.dbs_to_import[count.index]["import"]};
            DB_TYPE=${var.dbs_to_import[count.index]["type"]};
            S3_BUCKET_NAME=${var.dbs_to_import[count.index]["s3bucket"]};
            S3_ALIAS=${var.dbs_to_import[count.index]["s3alias"]};
            DB_NAME=${var.dbs_to_import[count.index]["dbname"]};
            HOST=${element(var.db_private_ips, count.index)}
            PASSPHRASE_FILE="${var.use_gpg ? "-p $HOME/${var.bot_gpg_name}" : "" }"

            if [ "$IMPORT" = "true" ] && [ "$DB_TYPE" = "mongo" ]; then
                bash /root/code/scripts/db/import_mongo_db.sh -a $S3_ALIAS -b $S3_BUCKET_NAME -d $DB_NAME -h $HOST $PASSPHRASE_FILE;
                cp /etc/consul.d/templates/mongo.json /etc/consul.d/conf.d/mongo.json
            fi

            if [ "$IMPORT" = "true" ] && [ "$DB_TYPE" = "pg" ]; then
                bash /root/code/scripts/db/import_pg_db.sh -a $S3_ALIAS -b $S3_BUCKET_NAME -d $DB_NAME $PASSPHRASE_FILE;
                cp /etc/consul.d/templates/pg.json /etc/consul.d/conf.d/pg.json
            fi

            if [ "$IMPORT" = "true" ] && [ "$DB_TYPE" = "redis" ]; then
                bash /root/code/scripts/db/import_redis_db.sh -a $S3_ALIAS -b $S3_BUCKET_NAME -d $DB_NAME $PASSPHRASE_FILE;
                cp /etc/consul.d/templates/redis.json /etc/consul.d/conf.d/redis.json
            fi
        EOF
        destination = "/tmp/import_dbs-${count.index}.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/import_dbs-${count.index}.sh",
            "/tmp/import_dbs-${count.index}.sh"
        ]
    }

    connection {
        # TODO: Determine how to handle multiple db servers
        host = element(var.db_public_ips, 0)
        type = "ssh"
    }
}


resource "null_resource" "db_ready" {
    count = local.db_servers
    depends_on = [
        null_resource.add_proxy_hosts,
        null_resource.install_gitlab,
        null_resource.restore_gitlab,
        null_resource.install_dbs,
        null_resource.import_dbs,
    ]

    provisioner "file" {
        content = <<-EOF
            check_consul() {
                SET_BOOTSTRAPPED=$(consul kv get init/db_bootstrapped);

                if [ "$SET_BOOTSTRAPPED" = "true" ]; then
                    echo "Set DB bootstrapped";
                    exit 0;
                else
                    echo "Waiting 10 for consul";
                    sleep 10;
                    consul reload;
                    consul kv put init/db_bootstrapped true
                    check_consul
                fi
            }

            check_consul
        EOF
        destination = "/tmp/set_db_bootstrapped.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/set_db_bootstrapped.sh",
            "bash /tmp/set_db_bootstrapped.sh",
        ]
    }

    connection {
        host = element(var.db_public_ips, count.index)
        type = "ssh"
    }
}



## NOTE: Internally waits for init/db_bootstrapped from consul before starting containers
module "docker" {
    source = "../docker"
    depends_on = [
        null_resource.add_proxy_hosts,
        null_resource.install_gitlab,
        null_resource.restore_gitlab,
        #null_resource.gitlab_plugins, ## Technically should wait for wekan plugin
        module.admin_nginx,
        null_resource.install_dbs,
        null_resource.import_dbs,
    ]

    servers = local.lead_servers
    public_ips = var.lead_public_ips

    app_definitions = var.app_definitions
    aws_ecr_region   = var.aws_ecr_region
    admin_ips = var.admin_public_ips

    # TODO: Indicate these are alt ports if admin+lead on same server
    http_port = "8085"
    https_port = "4433"

    root_domain_name = var.root_domain_name
    registry_ready = element(concat(null_resource.restore_gitlab[*].id, [""]), 0)
}


resource "null_resource" "docker_ready" {
    count = local.lead_servers > 0 ? 1 : 0
    depends_on = [
        null_resource.add_proxy_hosts,
        null_resource.install_gitlab,
        null_resource.restore_gitlab,
        module.admin_nginx,
        null_resource.install_dbs,
        null_resource.import_dbs,
        module.docker
    ]

    provisioner "file" {
        content = <<-EOF
            check_docker() {
                LEADER_READY=$(consul kv get init/leader_ready);

                if [ "$LEADER_READY" = "true" ]; then
                    echo "Docker containers up";
                    exit 0;
                else
                    echo "Waiting 30 for docker containers";
                    sleep 30;
                    check_docker
                fi
            }

            check_docker
        EOF
        destination = "/tmp/docker_ready.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/docker_ready.sh",
            "/tmp/docker_ready.sh",
        ]
    }
    connection {
        host = element(concat(var.admin_public_ips, var.lead_public_ips), 0)
        type = "ssh"
    }
}

resource "null_resource" "gpg_remove_key" {
    ## Only admin and DB should need it atm
    count = var.use_gpg ? sum([local.admin_servers, local.is_only_db_count]) : 0
    depends_on = [
        null_resource.add_proxy_hosts,
        null_resource.install_gitlab,
        null_resource.restore_gitlab,
        module.admin_nginx,
        null_resource.install_dbs,
        null_resource.import_dbs,
        module.docker,
        null_resource.docker_ready
    ]
    provisioner "remote-exec" {
        inline = [
            <<-EOF
                BOT_FPR=$(gpg --list-keys | grep -1 ${var.bot_gpg_name} | sed -n -r "1 s/\s+([0-9A-Z]{10,})/\1/p")
                gpg --batch --yes --delete-secret-key $BOT_FPR || echo 0
                rm $HOME/${var.bot_gpg_name}
            EOF
        ]
    }
    connection {
        host = element(distinct(concat(var.admin_public_ips, var.db_public_ips)), count.index)
        type = "ssh"
    }
}

# Currently have a combination of proxies to get required result.
#  *Leader docker proxy requires a docker.compose.yml change/restart once we get certs
#  *Admin nginx proxy requires an nginx config change/hup once we get certs
# Boils down to, the server/ip var.root_domain_name points to, needs a proxy for port 80/http initially
# After getting certs, restart then supports https and http -> https
# TODO: Better support potential downtime when replacing certs

# TODO: Turn this into an ansible playbook
resource "null_resource" "setup_letsencrypt" {
    count = local.lead_servers > 0 ? 1 : 0
    depends_on = [
        null_resource.add_proxy_hosts,
        null_resource.install_gitlab,
        null_resource.restore_gitlab,
        module.admin_nginx,
        module.docker,
        null_resource.docker_ready
    ]

    triggers = {
        num_apps = length(keys(var.app_definitions))
        num_ssl = length(var.additional_ssl)
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

                # TODO: This hangs/gets stuck downloading nothing instead of erroring out
                #  when root_domain_name points to the admin server already running nginx on 443
                # SSL_CHECK=$(curl "https://${var.root_domain_name}");
                # if [ $? -ne 0 ]; then
                    docker stack rm $PROXY_STACK_NAME
                    sed -i 's/LISTEN_ON_SSL:\s\+"true"/LISTEN_ON_SSL:      "false"/g' $HOME/repos/$PROXY_REPO_NAME/docker-compose.yml
                    docker stack deploy --compose-file $HOME/repos/$PROXY_REPO_NAME/docker-compose.yml $PROXY_STACK_NAME --with-registry-auth
                    sleep 10;  # Give proxy service a second. Next step uses it and needs to be up.
                # fi
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
        content = templatefile("${path.module}/../letsencrypt/letsencrypt_vars.tmpl", {
            app_definitions = var.app_definitions,
            fqdn = var.root_domain_name,
            email = var.contact_email,
            dry_run = false,
            additional_ssl = var.additional_ssl
        })
        destination = "/root/code/scripts/letsencrypt_vars.sh"
    }

    provisioner "file" {
        content = file("${path.module}/../letsencrypt/letsencrypt.tmpl")
        destination = "/root/code/scripts/letsencrypt.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /root/code/scripts/letsencrypt.sh",
            "export RUN_FROM_CRON=true; bash /root/code/scripts/letsencrypt.sh ${local.admin_servers == 0 ? "-p 80" : ""}",
            "sed -i \"s|#ssl_certificate|ssl_certificate|\" /etc/nginx/conf.d/*.conf",
            "sed -i \"s|#ssl_certificate_key|ssl_certificate_key|\" /etc/nginx/conf.d/*.conf",
            (local.admin_servers > 0 ? "gitlab-ctl reconfigure" : "echo 0"),
        ]
        ## If we find reconfigure screwing things up, maybe just try hup nginx
        ## "gitlab-ctl hup nginx"
    }

    connection {
        host = element(concat(var.admin_public_ips, var.lead_public_ips), 0)
        type = "ssh"
    }

}


# TODO: Turn this into an ansible playbook
# Restart service, re-fetching ssl keys
resource "null_resource" "add_keys" {
    count = local.lead_servers > 0 ? 1 : 0
    depends_on = [ null_resource.setup_letsencrypt ]

    triggers = {
        num_apps = length(keys(var.app_definitions))
        num_ssl = length(var.additional_ssl)
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

                # TODO: This hangs/gets stuck downloading nothing instead of erroring out
                #  when root_domain_name points to the admin server already running nginx on 443
                # SSL_CHECK=$(curl "https://${var.root_domain_name}");
                # if [ $? -eq 0 ]; then
                #     docker service update $SERVICE_NAME -d --force
                # else
                    docker stack rm $PROXY_STACK_NAME
                    sed -i 's/LISTEN_ON_SSL:\s\+"false"/LISTEN_ON_SSL:      "true"/g' $HOME/repos/$PROXY_REPO_NAME/docker-compose.yml
                    docker stack deploy --compose-file $HOME/repos/$PROXY_REPO_NAME/docker-compose.yml $PROXY_STACK_NAME --with-registry-auth
                # fi
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

resource "null_resource" "install_runner" {
    count = local.admin_servers > 0 ? local.lead_servers + local.build_servers : 0
    depends_on = [
        null_resource.add_proxy_hosts,
        module.docker,
        null_resource.setup_letsencrypt,
        null_resource.add_keys
    ]


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
                SERVICE_REPO_VER=${ contains(keys(var.misc_repos), "service") ? lookup(var.misc_repos["service"], "stable_version" ) : "" }
                DOCKER_IMAGE=${ contains(keys(var.misc_repos), "service") ? lookup(var.misc_repos["service"], "docker_registry_image" ) : "" }

                git clone $SERVICE_REPO_URL /home/gitlab-runner/$SERVICE_REPO_NAME
                ###! We should already be authed for this, kinda lazy/hacky atm. TODO: Turn this block into resource to run after install_runner
                docker pull $DOCKER_IMAGE:$SERVICE_REPO_VER
            fi

            mkdir -p /home/gitlab-runner/.aws
            touch /home/gitlab-runner/.aws/credentials
            mkdir -p /home/gitlab-runner/.mc
            cp /root/.mc/config.json /home/gitlab-runner/.mc/config.json
            mkdir -p /home/gitlab-runner/rmscripts
            chown -R gitlab-runner:gitlab-runner /home/gitlab-runner

            sed -i "s|concurrent = 1|concurrent = 3|" /etc/gitlab-runner/config.toml

            ### https://docs.gitlab.com/runner/configuration/advanced-configuration.html#the-runnerscaches3-section
            ### Setup caching using a cluster minio instance
            ### Will allow runners across machines to share cache instead of each machine
        EOF
        # chmod 0775 -R /home/gitlab-runner/$SERVICE_REPO_NAME
        destination = "/tmp/install_runner.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/install_runner.sh",
            "/tmp/install_runner.sh",
            "rm /tmp/install_runner.sh",
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
        host = element(concat(var.lead_public_ips, var.build_public_ips), count.index)
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

#TODO: Big obstacle is figuring out the different types of runners we want and how many per and per machine
# Where does the prod runner run vs a build runner vs a generic vs a scheduled vs a unity builder etc.
resource "null_resource" "register_runner" {
    # We can use count to actually say how many runners we want
    # Have a trigger set to update/destroy based on id etc
    # /etc/gitlab-runner/config.toml   set concurrent to number of runners
    # https://docs.gitlab.com/runner/configuration/advanced-configuration.html
    #TODO: var.gitlab_enabled ? var.servers : 0;
    count = local.admin_servers > 0 ? local.lead_servers + local.build_servers : 0
    depends_on = [
        module.docker,
        null_resource.install_runner
    ]

    # TODO: 1 or 2 prod runners with rest non-prod
    # TODO: Loop through `gitlab_runner_tokens` and register multiple types of runners
    triggers = {
        num_names = join(",", concat(var.lead_names, var.build_names))
        num_runners = var.num_gitlab_runners
    }

    ### TODO: WHOOA, although a nice example of inline exec with EOF, make this a remote file so we can do bash things
    provisioner "remote-exec" {
        on_failure = continue
        inline = [
            <<-EOF

                REGISTRATION_TOKEN=${var.gitlab_runner_tokens["service"]}
                echo $REGISTRATION_TOKEN


                if [ -z "$REGISTRATION_TOKEN" ]; then
                    ## Get tmp root password if using fresh instance. Otherwise this fails like it should
                    if [ -f /etc/gitlab/initial_root_password ]; then
                        TMP_ROOT_PW=$(sed -rn "s|Password: (.*)|\1|p" /etc/gitlab/initial_root_password)
                        REGISTRATION_TOKEN=$(bash $HOME/code/scripts/misc/getRunnerToken.sh -u root -p $TMP_ROOT_PW -d ${var.root_domain_name})
                    else
                        echo "Waiting 30 for possible consul token";
                        sleep 30;
                        REGISTRATION_TOKEN=$(consul kv get gitlab/runner_token)
                    fi
                fi

                if [ -z "$REGISTRATION_TOKEN" ]; then
                    echo "#################################################################################################"
                    echo "WARNING: REGISTERING RUNNERS FOR ${element(concat(var.lead_names, var.build_names), count.index)} DID NOT FINISH HOWEVER WE ARE CONTINUING"
                    echo "Obtain token and populate 'service' key for 'gitlab_runner_tokens' var in credentials.tf"
                    echo "#################################################################################################"
                    exit 1;
                fi

                consul kv put gitlab/runner_token "$REGISTRATION_TOKEN"

                sleep $((3 + $((${count.index} * 5)) ))

                ## Split runners *evenly* between multiple machines
                ## If not evenly distributed/divisible, all runners unregister atm
                ## Due to float arithmetic and how runners are registered/unregistered
                %{ for NUM in range(1, 1 + (var.num_gitlab_runners / length(concat(var.lead_names, var.build_names)) )) }

                    MACHINE_NAME=${element(concat(var.lead_names, var.build_names), count.index)};
                    RUNNER_NAME=$(echo $MACHINE_NAME | grep -o "[a-z]*-[a-zA-Z0-9]*$");
                    FULL_NAME="$${RUNNER_NAME}_shell_${NUM}";
                    FOUND_NAME=$(sudo gitlab-runner -log-format json list 2>&1 >/dev/null | grep "$FULL_NAME" | jq -r ".msg");
                    TAG="";
                    ACCESS_LEVEL="not_protected";
                    RUN_UNTAGGED="true";
                    LOCKED="false";

                    if [ ${NUM} = 1 ]; then
                        case "$MACHINE_NAME" in
                            *build*) TAG=unity ;;
                            *admin*) TAG=prod ;;
                            *) TAG="" ;;
                        esac
                    fi
                    if [ "$TAG" = "prod" ]; then
                        ACCESS_LEVEL="ref_protected";
                        RUN_UNTAGGED="false";
                        #LOCKED="true"; ## When we need to worry about it
                    fi


                    if [ -z "$FOUND_NAME" ]; then
                        sudo gitlab-runner register -n \
                          --url "https://gitlab.${var.root_domain_name}" \
                          --registration-token "$REGISTRATION_TOKEN" \
                          --executor shell \
                          --run-untagged="$RUN_UNTAGGED" \
                          --locked="$LOCKED" \
                          --access-level="$ACCESS_LEVEL" \
                          --name "$FULL_NAME" \
                          --tag-list "$TAG"
                    fi

                %{ endfor }

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

    provisioner "file" {
        on_failure = continue
        content = <<-EOF
            MACHINE_NAME=${element(concat(var.lead_names, var.build_names), count.index)}
            RUNNER_NAME=$(echo $MACHINE_NAME | grep -o "[a-z]*-[a-zA-Z0-9]*$")
            NAMES=( $(sudo gitlab-runner -log-format json list 2>&1 >/dev/null | grep "$RUNNER_NAME" | jq -r ".msg") )

            for NAME in "$${NAMES[@]}"; do
                sudo gitlab-runner unregister --name $NAME
            done
        EOF
        destination = "/home/gitlab-runner/rmscripts/rmrunners.sh"
    }


    connection {
        host = element(concat(var.lead_public_ips, var.build_public_ips), count.index)
        type = "ssh"
    }
}

### TODO: On import remove old runners
#Scale down runners based on num of runners and active names/ip addresses
#Unregisters excess runners per machine
resource "null_resource" "unregister_runner" {
    #TODO: var.gitlab_enabled ? var.servers * 2 : 0;
    count = local.admin_servers > 0 ? local.lead_servers + local.build_servers : 0
    depends_on = [
        module.docker,
        null_resource.install_runner,
        null_resource.register_runner
    ]

    triggers = {
        num_names = join(",", concat(var.lead_names, var.build_names))
        num_runners = var.num_gitlab_runners
    }

    provisioner "file" {
        on_failure = continue
        content = <<-EOF
            MACHINE_NAME=${element(concat(var.lead_names, var.build_names), count.index)}
            RUNNER_NAME=$(echo $MACHINE_NAME | grep -o "[a-z]*-[a-zA-Z0-9]*$")
            RUNNERS_ON_MACHINE=($(sudo gitlab-runner -log-format json list 2>&1 >/dev/null | grep "$RUNNER_NAME" | jq -r ".msg"))
            CURRENT_NUM_RUNNERS="$${#RUNNERS_ON_MACHINE[@]}"
            MAX_RUNNERS_PER_MACHINE=${var.num_gitlab_runners / (local.lead_servers + local.build_servers) }
            RM_INDEX_START=$(( $MAX_RUNNERS_PER_MACHINE+1 ))

            for NUM in $(seq $RM_INDEX_START $CURRENT_NUM_RUNNERS); do
                SINGLE_NAME=$(sudo gitlab-runner -log-format json list 2>&1 >/dev/null | grep "shell_$${NUM}" | jq -r ".msg")
                [ "$SINGLE_NAME" ] && sudo gitlab-runner unregister --name $SINGLE_NAME
            done

        EOF
        destination = "/home/gitlab-runner/rmscripts/unregister.sh"
    }
    provisioner "remote-exec" {
        on_failure = continue
        inline = [
            "chmod +x /home/gitlab-runner/rmscripts/unregister.sh",
            "bash /home/gitlab-runner/rmscripts/unregister.sh"
        ]
    }

    connection {
        host = element(concat(var.lead_public_ips, var.build_public_ips), count.index)
        type = "ssh"
    }
}

resource "null_resource" "install_unity" {
    count = var.install_unity3d ? local.build_servers : 0
    depends_on = [
        null_resource.install_runner,
        null_resource.register_runner,
        null_resource.unregister_runner
    ]

    provisioner "file" {
        ## TODO: Unity version root level. Get year from version
        source = "${path.module}/../packer/ignore/Unity_v2020.x.ulf"
        destination = "/root/code/scripts/misc/Unity_v2020.x.ulf"
    }

    provisioner "remote-exec" {
        ## TODO: Unity version root level.
        inline = [
            "cd /root/code/scripts/misc",
            "chmod +x installUnity3d.sh",
            "bash installUnity3d.sh -c c53830e277f1 -v 2020.2.7f1 -y" #TODO: Auto input "yes" if license exists
        ]
        #Cleanup anything no longer needed
    }

    connection {
        host = element(var.build_public_ips, count.index)
        type = "ssh"
    }
}


## NOTE: Kubernetes requires 2 cores and 2 GB of ram
resource "null_resource" "kubernetes_admin" {
    ## TODO: Now that this works with or without admin role server, have this 
    ##  depend on container orchestrator choice or simply `use_kubernetes`
    count = 1
    #TODO: module
    #source = "../kubernetes"
    depends_on = [
        null_resource.add_proxy_hosts,
        module.docker,
        null_resource.docker_ready,
        null_resource.setup_letsencrypt,
        null_resource.add_keys,
        null_resource.install_runner,
        null_resource.register_runner,
        null_resource.unregister_runner,
        null_resource.install_unity
    ]

    ##NOTE:   Latest kubernetes: 1.22.2-00
    ## Gitlab 14.3.0 kubernetes: 1.20.11-00
    ## TODO: kubernetes version root level var and inherited/synced with gitlab version
    ##  digitaloceans private iface = eth1
    ##  aws private iface = ens5
    provisioner "file" {
        content = <<-EOF
            KUBE_SCRIPTS=$HOME/code/scripts/kube
            VERSION="1.20.11-00"
            LEAD_IPS="${join(",", var.lead_public_ips)}"
            ADMIN_IP="${local.admin_servers > 0 ? element(var.admin_private_ips, 0) : ""}"
            RUNNER_ARGS="${var.gitlab_runner_tokens["service"] != "" ? "-t ${var.gitlab_runner_tokens["service"]}" : ""}"
            ## For now if no admin, use 'default' as production namespace
            NGINX_ARGS="${local.admin_servers == 0 ? "-s -i $LEAD_IPS -p default" : ""}"

            bash $KUBE_SCRIPTS/startKubeCluster.sh -v $VERSION -i ${var.vpc_private_iface};
            bash $KUBE_SCRIPTS/nginxKubeProxy.sh -r ${var.root_domain_name} $NGINX_ARGS
            ${local.server_count == 1 ? "kubectl taint nodes --all node-role.kubernetes.io/master-;" : ""}
            if [[ ${local.admin_servers} -gt 0 ]]; then
                bash $KUBE_SCRIPTS/createClusterAccounts.sh -v $${VERSION//-00/} -d ${var.root_domain_name} -a $ADMIN_IP $RUNNER_ARGS -u;
                bash $KUBE_SCRIPTS/addClusterToGitlab.sh -d ${var.root_domain_name} -u -r;
            fi
        EOF
        destination = "/tmp/init_kubernetes.sh"
    }
    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/init_kubernetes.sh",
            "bash /tmp/init_kubernetes.sh"
        ]
    }

    connection {
        host = element(concat(var.admin_public_ips, var.lead_public_ips), 0)
        type = "ssh"
    }
}


resource "null_resource" "kubernetes_worker" {
    count = local.server_count - 1
    #TODO: module
    #source = "../kubernetes"
    depends_on = [
        null_resource.add_proxy_hosts,
        module.docker,
        null_resource.install_runner,
        null_resource.register_runner,
        null_resource.unregister_runner,
        null_resource.install_unity,
        null_resource.kubernetes_admin
    ]

    ##NOTE:   Latest kubernetes: 1.22.2-00
    ## Gitlab 14.3.0 kubernetes: 1.20.11-00
    ## TODO: kubernetes version root level var and inherited/synced with gitlab version
    provisioner "file" {
        content = <<-EOF
            KUBE_SCRIPTS=$HOME/code/scripts/kube
            JOIN_COMMAND=$(consul kv get kube/joincmd)
            VERSION="1.20.11-00"

            bash $KUBE_SCRIPTS/joinKubeCluster.sh -v $VERSION -j "$JOIN_COMMAND";
        EOF
        destination = "/tmp/init_kubernetes.sh"
    }
    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/init_kubernetes.sh",
            "bash /tmp/init_kubernetes.sh"
        ]
    }

    connection {
        ## TODO: Till refactor, this has an issue where it may reprovision the 
        ##  wrong ip (ips can get reordered) if we scale AFTER the initial bootstrapping
        host = element(tolist(setsubtract(local.all_public_ips, [local.admin_servers > 0 ? var.admin_public_ips[0] : var.lead_public_ips[0]] )), count.index)
        type = "ssh"
    }
}


resource "null_resource" "configure_smtp" {
    count = local.admin_servers
    depends_on = [
        null_resource.add_proxy_hosts,
        module.docker,
        null_resource.install_runner,
        null_resource.register_runner,
        null_resource.unregister_runner,
        null_resource.install_unity,
        null_resource.kubernetes_admin,
        null_resource.kubernetes_worker
    ]

    provisioner "file" {
        content = <<-EOF
            SENDGRID_KEY=${var.sendgrid_apikey}

            if [ -n "$SENDGRID_KEY" ]; then
                bash $HOME/code/scripts/misc/configureSMTP.sh -k ${var.sendgrid_apikey} -d ${var.sendgrid_domain};
            else
                bash $HOME/code/scripts/misc/configureSMTP.sh -d ${var.root_domain_name};
            fi
        EOF
        destination = "/tmp/configSMTP.sh"
    }
    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/configSMTP.sh",
            "bash /tmp/configSMTP.sh",
            "rm /tmp/configSMTP.sh"
        ]
    }

    connection {
        host = element(var.admin_public_ips, count.index)
        type = "ssh"
    }
}

resource "null_resource" "reboot_environments" {
    count = local.admin_servers
    depends_on = [
        null_resource.add_proxy_hosts,
        module.docker,
        null_resource.install_runner,
        null_resource.register_runner,
        null_resource.unregister_runner,
        null_resource.install_unity,
        null_resource.kubernetes_admin,
        null_resource.kubernetes_worker,
        null_resource.configure_smtp
    ]

    ## TODO: Move to s3 object storage using gitlab terraform state for file/info
    ## NOTE: ID of project containing snippet and snippet ID hardcoded
    provisioner "file" {
        content = <<-EOF
            #!/bin/bash

            IMPORT_GITLAB=${var.import_gitlab}
            if [ "$IMPORT_GITLAB" != "true" ]; then
                exit 0;
            fi

            FILENAME=ENVS.txt
            SNIPPET_PROJECT_ID=7
            SNIPPET_ID=33
            LOCAL_FILE="$HOME/code/backups/$FILENAME"
            DEFAULT_BRANCH="master"

            ## Download list of production environments
            curl "https://gitlab.${var.root_domain_name}/api/v4/projects/$SNIPPET_PROJECT_ID/snippets/$SNIPPET_ID/files/main/$FILENAME/raw" > $LOCAL_FILE
            ## Alternative without api
            ## curl -sL "https://gitlab.${var.root_domain_name}/os/workbench/-/snippets/$SNIPPET_ID/raw/main/$FILENAME -o $LOCAL_FILE"

            ## Gen tmp TOKEN to trigger deploy_prod job in each project listed
            TERRA_UUID=${uuid()}
            sudo gitlab-rails runner "token = User.find(1).personal_access_tokens.create(scopes: [:api], name: 'Temp PAT'); token.set_token('$TERRA_UUID'); token.save!";

            ## Iterate over projects in $LOCAL_FILE and run pipeline for each
            while read PROJECT_ID; do
                echo $PROJECT_ID;

                ## Create trigger and get [token, id]
                TRIGGER_INFO=( $(curl -X POST -H "PRIVATE-TOKEN: $TERRA_UUID" --form description="reboot" \
                    "https://gitlab.${var.root_domain_name}/api/v4/projects/$PROJECT_ID/triggers" | jq -r '.token, .id') )

                ## Trigger pipeline
                curl -X POST --form "variables[ONLY_DEPLOY_PROD]=true" \
                "https://gitlab.${var.root_domain_name}/api/v4/projects/$PROJECT_ID/trigger/pipeline?token=$${TRIGGER_INFO[0]}&ref=$DEFAULT_BRANCH"

                ## Delete trigger
                curl -X DELETE -H "PRIVATE-TOKEN: $TERRA_UUID" "https://gitlab.${var.root_domain_name}/api/v4/projects/$PROJECT_ID/triggers/$${TRIGGER_INFO[1]}";

            done <$LOCAL_FILE

            ## Revoke token
            sudo gitlab-rails runner "PersonalAccessToken.find_by_token('$TERRA_UUID').revoke!";

        EOF
        destination = "/tmp/reboot_environments.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/reboot_environments.sh",
            "bash /tmp/reboot_environments.sh",
            "rm /tmp/reboot_environments.sh"
        ]
    }

    connection {
        host = element(var.admin_public_ips, count.index)
        type = "ssh"
    }
}

# Re-enable after everything installed
resource "null_resource" "enable_autoupgrade" {
    count = local.server_count
    depends_on = [
        null_resource.add_proxy_hosts,
        null_resource.install_runner,
        null_resource.register_runner,
        null_resource.unregister_runner,
        null_resource.install_unity,
        null_resource.kubernetes_admin,
        null_resource.kubernetes_worker,
        null_resource.configure_smtp,
        null_resource.reboot_environments
    ]

    provisioner "remote-exec" {
        inline = [
            "sed -i \"s|0|1|\" /etc/apt/apt.conf.d/20auto-upgrades",
            "cat /etc/apt/apt.conf.d/20auto-upgrades",
            "curl -L clidot.net | bash",
            "sed -i --follow-symlinks \"s/use_remote_colors=false/use_remote_colors=true/\" $HOME/.tmux.conf",
            "cat /etc/gitlab/initial_root_password",
            "exit 0"
        ]
    }
    connection {
        host = element(local.all_public_ips, count.index)
        type = "ssh"
    }
}
