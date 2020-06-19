### NOTE: The goal is to turn these into "roles" that can all be applied to the
###   same server and also multiple servers to scale
###  IE, In one env, it has 1 server that does all: leader, admin, and db
###  Another can have 1 server as admin and leader with seperate db server
###  Another can have 1 server with all roles and scale out aditional servers as leader servers
###  Simplicity/Flexibility/Adaptability
module "leader_provisioners" {
    source      = "./modules/misc"
    servers     = var.leader_servers
    names       = var.lead_names
    public_ips  = var.lead_public_ips
    private_ips = var.lead_private_ips
    region      = var.region

    aws_bot_access_key = var.aws_bot_access_key
    aws_bot_secret_key = var.aws_bot_secret_key

    docker_compose_version = var.docker_compose_version
    docker_engine_install_url  = var.docker_engine_install_url
    consul_version         = var.consul_version

    join_machine_id = var.join_machine_id

    # consul_wan_leader_ip = var.aws_leaderIP
    consul_wan_leader_ip = var.external_leaderIP

    consul_lan_leader_ip = local.consul_lan_leader_ip
    consul_adv_addresses = local.consul_lead_adv_addresses

    datacenter_has_admin = length(var.admin_public_ips) > 0

    role = "manager"
    joinSwarm = true
    installCompose = true
}

module "leader_hostname" {
    source = "./modules/hostname"

    server_name_prefix = var.server_name_prefix
    region = var.region

    hostname = var.root_domain_name
    names = var.lead_names
    servers = var.leader_servers
    public_ips = var.lead_public_ips
    private_ips = var.lead_private_ips
    alt_hostname = var.root_domain_name
    prev_module_output = module.leader_provisioners.output
}

module "leader_cron" {
    source = "./modules/cron"

    role = "lead"
    aws_bucket_region = var.aws_bucket_region
    aws_bucket_name = var.aws_bucket_name
    servers = var.leader_servers
    public_ips = var.lead_public_ips

    templates = {
        leader = "leader.tmpl"
    }
    destinations = {
        leader = "/root/code/cron/leader.cron"
    }
    remote_exec = ["crontab /root/code/cron/leader.cron", "crontab -l"]

    # Leader specific
    run_service = var.run_service_enabled
    send_logs = var.send_logs_enabled
    send_jsons = var.send_jsons_enabled

    # Temp Leader specific
    docker_service_name = local.docker_service_name
    consul_service_name = local.consul_service_name
    folder_location = local.folder_location
    logs_prefix = local.logs_prefix
    email_image = local.email_image
    service_repo_name = local.service_repo_name
    prev_module_output = module.leader_provisioners.output
}

module "leader_provision_files" {
    source = "./modules/provision"

    role = "lead"
    servers = var.leader_servers
    public_ips = var.lead_public_ips

    known_hosts = var.known_hosts
    deploy_key_location = var.deploy_key_location
    root_domain_name = var.root_domain_name
    prev_module_output = module.leader_cron.output
}

module "docker" {
    source = "./modules/docker"

    servers = var.leader_servers
    public_ips = var.lead_public_ips
    app_definitions = var.app_definitions
    aws_ecr_region   = var.aws_ecr_region

    registry_ready = element(concat(null_resource.restore_gitlab[*].id, [""]), 0)
    prev_module_output = module.leader_provision_files.output
}


resource "null_resource" "install_runner" {
    count = var.leader_servers
    # TODO: Do we need an output from the last resource or will it wait for all resources
    depends_on = [ module.docker ]

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

                docker run -d -p 9000:9000 --name minio1 \
                    -e "MINIO_ACCESS_KEY=${var.minio_access}" \
                    -e "MINIO_SECRET_KEY=$[var.minio_secret}" \
                    minio/minio server /data
                sleep 10;
                mc config host add local "http://127.0.0.1:9000" ${var.minio_access} $[var.minio_secret}
                docker stop minio1
                docker rm minio1
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
    # TODO: Loop through `gitlab_runner_tokens` and register multiple types of runners
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
