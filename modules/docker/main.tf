variable "ansible_hosts" {}
variable "ansible_hostfile" {}
variable "predestroy_hostfile" {}

variable "lead_servers" {}
variable "region" { default = "" }
variable "aws_ecr_region" { default = "" }
variable "root_domain_name" {}
variable "container_orchestrators" {}

variable "app_definitions" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string, docker_registry=string, docker_registry_image=string,
        docker_registry_url=string, docker_registry_user=string, docker_registry_pw=string, service_name=string,
        green_service=string, blue_service=string, default_active=string, subdomain_name=string
        use_custom_restore=string, custom_restore_file=string, custom_init=string, custom_vars=string
    }))
}

locals {
    lead_public_ips = [
        for HOST in var.ansible_hosts:
        HOST.ip
        if contains(HOST.roles, "lead")
    ]
    lead_names = [
        for HOST in var.ansible_hosts:
        HOST.name
        if contains(HOST.roles, "lead")
    ]
}

resource "null_resource" "swarm_rm_nodes" {
    count = contains(var.container_orchestrators, "docker_swarm") ? 1 : 0

    triggers = {
        num_lead = var.lead_servers
    }

    ## Run playbook with old ansible file and new names to find out the ones to be deleted, drain and removing them
    provisioner "local-exec" {
        command = <<-EOF
            if [ -f "${var.predestroy_hostfile}" ]; then
                ansible-playbook ${path.module}/playbooks/swarm_rm.yml -i ${var.predestroy_hostfile} \
                    --extra-vars 'lead_names=${jsonencode(local.lead_names)} lead_public_ips=${jsonencode(local.lead_public_ips)}';
            fi
        EOF
    }
}

resource "null_resource" "swarm" {
    count = contains(var.container_orchestrators, "docker_swarm") ? 1 : 0
    depends_on = [null_resource.swarm_rm_nodes]
    triggers = {
        num_lead = var.lead_servers
    }
    provisioner "local-exec" {
        command = "ansible-playbook ${path.module}/playbooks/swarm.yml -i ${var.ansible_hostfile} --extra-vars \"region=${var.region}\""
    }
}



## TODO: Use for_each to use keys instead of indexes
resource "null_resource" "pull_images" {
    count = contains(var.container_orchestrators, "docker_swarm") ? var.lead_servers : 0
    depends_on = [
        null_resource.swarm_rm_nodes,
        null_resource.swarm,
    ]

    triggers = {
        num_apps = length(keys(var.app_definitions))
    }

    provisioner "remote-exec" {
        # TODO: Have production always pull stable

        # TODO: Need to use correct Docker Registry credentials per Docker Image to log in to that registry
        # TODO: make sure we're also using the correct login region

        # TODO: Seperate out docker credentials from git credentials. docker pull vs git clone
        inline = [
            <<-EOF

                %{ for APP in var.app_definitions }

                    PULL=${APP["pull"]};
                    STABLE_VER=${APP["stable_version"]};
                    USE_STABLE=${APP["use_stable"]};
                    REPO_URL=${APP["repo_url"]};
                    REPO_NAME=${APP["repo_name"]};
                    DOCKER_REGISTRY=${APP["docker_registry"]};
                    DOCKER_IMAGE=${APP["docker_registry_image"]};
                    DOCKER_REGISTRY_URL=${APP["docker_registry_url"]};
                    DOCKER_USER=${APP["docker_registry_user"]};
                    DOCKER_PW=${APP["docker_registry_pw"]};

                    if [ "$PULL" = "true" ]; then

                        if [ "$DOCKER_REGISTRY" = "aws_ecr" ]; then
                            LOGIN=$(aws ecr get-login --region ${var.aws_ecr_region} --no-include-email)
                            $LOGIN
                        fi

                        if [ "$DOCKER_REGISTRY" = "docker_hub" ] && [ -n "$DOCKER_USER" ] && [ -n "$DOCKER_PW" ]; then
                            docker login -u $DOCKER_USER -p $DOCKER_PW
                        fi

                        if [ "$DOCKER_REGISTRY" = "gitlab" ] && [ -n "$DOCKER_USER" ] && [ -n "$DOCKER_PW" ] && [ -n "$DOCKER_REGISTRY_URL" ]; then
                            # TODO: Registry Url or create deploy token for each repo
                            docker login -u $DOCKER_USER -p $DOCKER_PW $DOCKER_REGISTRY_URL
                        fi

                        git clone $REPO_URL /root/repos/$REPO_NAME
                        [ -n "$DOCKER_IMAGE" ] && docker pull $DOCKER_IMAGE:latest
                        (cd /root/repos/$REPO_NAME && git checkout master);

                        if [ -n "$STABLE_VER" ]; then
                            docker pull $DOCKER_IMAGE:$STABLE_VER;
                        fi

                        if [ "$USE_STABLE" = "true" ]; then
                            (cd /root/repos/$REPO_NAME && git checkout tags/$STABLE_VER);
                        fi
                    fi

                    sleep 10;

                %{ endfor }

                exit 0
            EOF
        ]
        connection {
            host = element(local.lead_public_ips, count.index)
            type = "ssh"
        }
    }
}

## TODO: Use for_each to use keys instead of indexes
resource "null_resource" "start_containers" {
    count = contains(var.container_orchestrators, "docker_swarm") ? 1 : 0
    depends_on = [
        null_resource.swarm_rm_nodes,
        null_resource.swarm,
        null_resource.pull_images,
    ]

    triggers = {
        num_apps = length(keys(var.app_definitions))
    }

    provisioner "remote-exec" {
        # TODO: Adjustable DOCKER_OVERLAY_SUBNET
        inline = [
            <<-EOF

                DOCKER_OVERLAY_SUBNET="192.168.0.0/16"

                NET_UP=$(docker network inspect proxy)
                if [ $? -eq 1 ]; then docker network create --attachable --driver overlay --subnet $DOCKER_OVERLAY_SUBNET proxy; fi

                %{ for APP in var.app_definitions }

                    GREEN_SERVICE=${APP["green_service"]};
                    CLEAN_SERVICE_NAME=$(echo $GREEN_SERVICE | grep -Eo "[a-z_]+");
                    REPO_NAME=${APP["repo_name"]};
                    SERVICE_NAME=${APP["service_name"]};
                    CUSTOM_INIT=${APP["custom_init"]}
                    CUSTOM_VARS="${APP["custom_vars"]}"
                    USE_CUSTOM_RESTORE=${APP["use_custom_restore"]}
                    CUSTOM_RESTORE="${APP["custom_restore_file"]}"


                    if [ "$REPO_NAME" = "wekan" ]; then
                        # TODO: Start using gitlab healthchecks instead of waiting
                        echo "Waiting 90s for gitlab api for oauth plugins";
                        sleep 90;

                        MONGO_IP=$(curl -sS "http://localhost:8500/v1/catalog/service/mongo" | jq -r ".[].Address")
                        sed -i "s|mongodb://mongo_url:27017|mongodb://$MONGO_IP:27017|" /root/repos/$REPO_NAME/docker-compose.yml;

                        FQDN=$(consul kv get domainname);
                        sed -i "s|http://wekan.example.com|https://wekan.$FQDN|" /root/repos/$REPO_NAME/docker-compose.yml;
                        sed -i "s|https://gitlab.example.com|https://gitlab.$FQDN|" /root/repos/$REPO_NAME/docker-compose.yml;

                        APP_ID=$(consul kv get wekan/app_id);
                        SECRET=$(consul kv get wekan/secret);
                        sed -i "s|OAUTH2_CLIENT_ID=.*|OAUTH2_CLIENT_ID=$APP_ID|g" /root/repos/$REPO_NAME/docker-compose.yml;
                        sed -i "s|OAUTH2_SECRET=.*|OAUTH2_SECRET=$SECRET|g" /root/repos/$REPO_NAME/docker-compose.yml;

                        sed -i "s|OAUTH2_ENABLED=false|OAUTH2_ENABLED=true|" /root/repos/$REPO_NAME/docker-compose.yml;
                    fi

                    APP_UP=$(docker service ps $CLEAN_SERVICE_NAME);
                    if [ -z "$APP_UP" ] && [ "$SERVICE_NAME" != "custom" ]; then
                        sed -i "s/condition: on-failure/condition: any/" /root/repos/$REPO_NAME/docker-compose.yml
                        (cd /root/repos/$REPO_NAME && docker stack deploy --compose-file docker-compose.yml $SERVICE_NAME --with-registry-auth)
                    fi

                    if [ "$SERVICE_NAME" = "custom" ]; then
                        (cd /root/repos/$REPO_NAME && echo "$CUSTOM_VARS" >> .custom_env && bash "$CUSTOM_INIT")
                    fi

                    if [ "$USE_CUSTOM_RESTORE" = "true" ]; then
                        sleep 10;
                        (cd /root/repos/$REPO_NAME && bash $CUSTOM_RESTORE)
                    fi


                %{ endfor }

                exit 0
            EOF
        ]
        connection {
            host = element(local.lead_public_ips, 0)
            type = "ssh"
        }
    }
}



# TODO: Move web specific things into docker_swarm resource
# resource "null_resource" "docker_web" {
#     count = 0 #length(distinct(var.web_public_ips)
#     depends_on = [null_resource.docker_init]
#
#     # Join a docker swarm
#     provisioner "local-exec" {
#         # TODO: We dont use web instances yet, but we should ensure that web instances joining the leaders/cluster ALSO
#         #   share the same docker version so we dont introduce swarm/load balancing/proxy bugs, like in docker_leader resource
#         # SWARM_DOCKER_VER=$(docker-machine ssh ${element(var.names, 1)} "docker -v;")
#         # CUR_DOCKER_VER=$(docker-machine ssh ${element(var.names, count.index)} "docker -v;")
#
#         command = <<-EOF
#             JOIN_CMD=$(docker-machine ssh ${var.docker_leader_name} "docker swarm join-token worker | grep -- --token;");
#             docker-machine ssh ${element(var.names, count.index)} "set -e; $JOIN_CMD;"
#
#             OLD_ID=$(docker-machine ssh ${var.docker_leader_name} "docker node ls --filter name=${element(var.names, count.index)} | grep Down | cut -d ' ' -f1;")
#             docker-machine ssh ${var.docker_leader_name} "docker node rm --force $OLD_ID;"
#             docker-machine ssh ${var.docker_leader_name} "docker node update --label-add dc=${var.region} --label-add name=${element(var.names, count.index)} ${element(var.names, count.index)}"
#         EOF
#     }
# }

