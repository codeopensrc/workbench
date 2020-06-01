
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

variable "provisioners_done" {}

resource "null_resource" "pull_docker_containers" {
    count = var.servers

    triggers = {
        my_dependencies = "${join(",", var.provisioners_done)}"
        num_apps = length(keys(var.app_definitions))
    }

    provisioner "remote-exec" {
        # TODO: Have production always pull stable

        # TODO: Need to use correct Docker Registry credentials per Docker Image to log in to that registry
        # TODO: make sure we're also using the correct login region
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

                    sleep 2;

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
