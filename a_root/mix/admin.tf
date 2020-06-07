### NOTE: The goal is to turn these into "roles" that can all be applied to the
###   same server and also multiple servers to scale
###  IE, In one env, it has 1 server that does all: leader, admin, and db
###  Another can have 1 server as admin and leader with seperate db server
###  Another can have 1 server with all roles and scale out aditional servers as leader servers
###  Simplicity/Flexibility/Adaptability
module "admin_provisioners" {
    source      = "./modules/misc"
    servers     = var.admin_servers
    names       = var.admin_names
    public_ips  = var.admin_public_ips
    private_ips = var.admin_private_ips
    region      = var.region

    aws_bot_access_key = var.aws_bot_access_key
    aws_bot_secret_key = var.aws_bot_secret_key

    docker_compose_version = var.docker_compose_version
    docker_engine_install_url  = var.docker_engine_install_url
    consul_version         = var.consul_version

    # TODO: This might cause a problem when launching the 2nd admin server when swapping
    consul_lan_leader_ip = local.consul_lan_leader_ip
    consul_adv_addresses = local.consul_admin_adv_addresses

    role = "admin"
}

module "admin_hostname" {
    source = "./modules/hostname"

    server_name_prefix = var.server_name_prefix
    region = var.region

    hostname = var.chef_server_url
    names = var.admin_names
    servers = var.admin_servers
    public_ips = var.admin_public_ips
    alt_hostname = "chef"
}

module "admin_cron" {
    source = "./modules/cron"

    role = "admin"
    aws_bucket_region = var.aws_bucket_region
    aws_bucket_name = var.aws_bucket_name
    servers = var.admin_servers
    public_ips = var.admin_public_ips

    templates = {
        admin = "admin.tmpl"
    }
    destinations = {
        admin = "/root/code/cron/admin.cron"
    }
    remote_exec = ["crontab /root/code/cron/admin.cron", "crontab -l"]

    # Admin specific
    gitlab_backups_enabled = var.gitlab_backups_enabled
    prev_module_output = module.admin_provisioners.output
}

module "admin_provision_files" {
    source = "./modules/provision"

    role = "admin"
    servers = var.admin_servers
    public_ips = var.admin_public_ips
    private_ips = var.admin_private_ips

    known_hosts = var.known_hosts
    deploy_key_location = var.deploy_key_location
    root_domain_name = var.root_domain_name
    prev_module_output = module.admin_cron.output
}


### NOTE: Only thing for this is consul needs to be installed
resource "null_resource" "add_proxy_hosts" {
    count      = var.admin_servers
    depends_on = [
        module.admin_provisioners,
        module.admin_hostname,
        module.admin_cron,
        module.admin_provision_files
    ]

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


resource "null_resource" "install_gitlab" {
    count = var.admin_servers
    depends_on = [ null_resource.add_proxy_hosts ]

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
        null_resource.add_proxy_hosts,
        null_resource.install_gitlab,
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


resource "null_resource" "docker_ready" {
    count = var.admin_servers
    depends_on = [
        null_resource.add_proxy_hosts,
        null_resource.install_gitlab,
        null_resource.restore_gitlab,
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
        host = element(var.admin_public_ips, count.index)
        type = "ssh"
    }
}

#### NOTE: Current problem is admin not allowing leader/db in though firewall, thus
####        a consul cluster leader not being chosen before the proxy_main service is brought online
#### NEW: null_resource.docker_ready is fixing this issue for now


#### TODO: NEEDS TO BE STANDALONE
# Needs to be run on a single node without external dependency
# All calls to subdmain -> leader server. Leader needs containers + db. Files need to be stored on admin (for now)
# Leader does ssl and somehow sync to admin. Or admin handles check, but does not require external leader/proxy
#   but does not also interupt leader/proxy

# TODO: Turn this into an ansible playbook
resource "null_resource" "setup_letsencrypt" {
    count = var.leader_servers > 0 ? 1 : 0
    depends_on = [
        null_resource.add_proxy_hosts,
        null_resource.install_gitlab,
        null_resource.restore_gitlab,
        null_resource.docker_ready,
    ]

    triggers = {
        num_apps = length(keys(var.app_definitions))
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

    connection {
        host = element(var.admin_public_ips, count.index)
        type = "ssh"
    }

}


# TODO: Turn this into an ansible playbook
# Restart service, re-fetching ssl keys
resource "null_resource" "add_keys" {
    count = var.leader_servers > 0 ? 1 : 0
    depends_on = [
        null_resource.add_proxy_hosts,
        null_resource.install_gitlab,
        null_resource.restore_gitlab,
        null_resource.docker_ready,
        null_resource.setup_letsencrypt
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
