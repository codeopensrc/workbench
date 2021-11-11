variable "servers" {}
variable "aws_ecr_region" { default = "" }
variable "public_ips" { default = [] }
variable "app_definitions" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string, docker_registry=string, docker_registry_image=string,
        docker_registry_url=string, docker_registry_user=string, docker_registry_pw=string, service_name=string,
        green_service=string, blue_service=string, default_active=string, subdomain_name=string
        use_custom_restore=string, custom_restore_file=string, custom_init=string, custom_vars=string
    }))
}
variable "root_domain_name" {}


## TODO: Use for_each to use keys instead of indexes
resource "null_resource" "pull_images" {
    count = var.servers

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
            host = element(var.public_ips, count.index)
            type = "ssh"
        }
    }
}

## TODO: Use for_each to use keys instead of indexes
resource "null_resource" "start_containers" {
    count = 1
    depends_on = [null_resource.pull_images]

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
            host = element(var.public_ips, 0)
            type = "ssh"
        }
    }
}
