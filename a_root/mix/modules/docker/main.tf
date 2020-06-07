
variable "servers" {}
variable "aws_ecr_region" { default = "" }
variable "public_ips" {
    type = list(string)
    default = []
}
variable "app_definitions" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string, docker_registry=string, docker_registry_image=string,
        docker_registry_url=string, docker_registry_user=string, docker_registry_pw=string, service_name=string,
        green_service=string, blue_service=string, default_active=string, create_subdomain=string, subdomain_name=string }))
}

variable "prev_module_output" {}
variable "registry_ready" {}

resource "null_resource" "pull_images" {
    count = var.servers

    triggers = {
        wait_for_prev_module = "${join(",", var.prev_module_output)}"
        num_apps = length(keys(var.app_definitions))
        registry_ready = var.registry_ready
    }

    provisioner "remote-exec" {
        # TODO: Have production always pull stable

        # TODO: Need to use correct Docker Registry credentials per Docker Image to log in to that registry
        # TODO: make sure we're also using the correct login region

        # TODO: Make sure images/gitlab are there before doing this stage.
        # Since deprecating chef we get to this stage far before gitlab is installed and restored
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
                        docker pull $DOCKER_IMAGE:latest;
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

resource "null_resource" "start_containers" {
    count = var.servers
    depends_on = [null_resource.pull_images]

    triggers = {
        num_apps = length(keys(var.app_definitions))
    }

    provisioner "remote-exec" {
        # TODO: Adjustable DOCKER_OVERLAY_SUBNET
        inline = [
            <<-EOF

                check_dbs() {
                    DB_READY=$(consul kv get init/db_bootstrapped);

                    if [ "$DB_READY" = "true" ]; then
                        echo "Starting containers";
                        start_containers;
                    else
                        echo "Waiting 30 for dbs to import";
                        sleep 30;
                        check_dbs;
                    fi
                }


                start_containers() {
                    DOCKER_OVERLAY_SUBNET="192.168.0.0/16"

                    NET_UP=$(docker network inspect proxy)
                    if [ $? -eq 1 ]; then docker network create --attachable --driver overlay --subnet $DOCKER_OVERLAY_SUBNET proxy; fi

                    ### NOTE: Once we move to blue/turquiose/green, we'll have to make
                    ###  sure we bring up the correct service (_blue or _green, not _main)

                    %{ for APP in var.app_definitions }

                        CHECK_SERVICE=${APP["green_service"]};
                        REPO_NAME=${APP["repo_name"]};
                        SERVICE_NAME=${APP["service_name"]};

                        APP_UP=$(docker service ps $CHECK_SERVICE)
                        [ -z "$APP_UP" ] && (cd /root/repos/$REPO_NAME && docker stack deploy --compose-file docker-compose.yml $SERVICE_NAME --with-registry-auth)

                    %{ endfor }

                    consul kv put init/leader_ready true;
                    exit 0
                }


                check_dbs

            EOF
        ]
        connection {
            host = element(var.public_ips, count.index)
            type = "ssh"
        }
    }
}
