variable "ansible_hostfile" {}
variable "gitlab_runner_tokens" {}

variable "lead_public_ips" {}
variable "build_public_ips" {}

variable "admin_servers" {}
variable "lead_servers" {}
variable "build_servers" {}

variable "lead_names" {}
variable "build_names" {}

variable "runners_per_machine" {}
variable "root_domain_name" {}


resource "null_resource" "install_runner" {
    count = var.admin_servers > 0 ? var.lead_servers + var.build_servers : 0

    provisioner "file" {
        content = <<-EOF
            curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo bash
            apt-cache madison gitlab-runner
            sudo apt-get install gitlab-runner jq -y
            sudo usermod -aG docker gitlab-runner

            mkdir -p /home/gitlab-runner/.mc
            cp /root/.mc/config.json /home/gitlab-runner/.mc/config.json
            mkdir -p /home/gitlab-runner/rmscripts
            chown -R gitlab-runner:gitlab-runner /home/gitlab-runner

            sed -i "s|concurrent = 1|concurrent = 3|" /etc/gitlab-runner/config.toml

            ### https://docs.gitlab.com/runner/configuration/advanced-configuration.html#the-runnerscaches3-section
            ### Setup caching using a cluster minio instance
            ### Will allow runners across machines to share cache instead of each machine
        EOF
        destination = "/tmp/install_runner.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/install_runner.sh",
            "/tmp/install_runner.sh",
        ]
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
    count = var.admin_servers > 0 ? var.lead_servers + var.build_servers : 0
    depends_on = [
        null_resource.install_runner
    ]

    # TODO: 1 or 2 prod runners with rest non-prod
    # TODO: Loop through `gitlab_runner_tokens` and register multiple types of runners
    triggers = {
        num_names = join(",", concat(var.lead_names, var.build_names))
        num_runners = sum([var.lead_servers + var.build_servers]) * var.runners_per_machine
    }

    ### TODO: WHOOA, although a nice example of inline exec with EOF, make this a remote file so we can do bash things
    provisioner "remote-exec" {
        on_failure = continue
        #TODO: If fresh gitlab install has lead role on a different server we dont have the initial_root_password
        # Maybe put the initial password in consul kv if we dont import since it should be changed anyway
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
                %{ for NUM in range(1, 1 + var.runners_per_machine) }

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
                            *lead*) TAG=prod ;;
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
    count = var.admin_servers > 0 ? var.lead_servers + var.build_servers : 0
    depends_on = [
        null_resource.install_runner,
        null_resource.register_runner
    ]

    triggers = {
        num_names = join(",", concat(var.lead_names, var.build_names))
        num_runners = sum([var.lead_servers + var.build_servers]) * var.runners_per_machine
    }

    provisioner "file" {
        on_failure = continue
        content = <<-EOF
            MACHINE_NAME=${element(concat(var.lead_names, var.build_names), count.index)}
            RUNNER_NAME=$(echo $MACHINE_NAME | grep -o "[a-z]*-[a-zA-Z0-9]*$")
            RUNNERS_ON_MACHINE=($(sudo gitlab-runner -log-format json list 2>&1 >/dev/null | grep "$RUNNER_NAME" | jq -r ".msg"))
            CURRENT_NUM_RUNNERS="$${#RUNNERS_ON_MACHINE[@]}"
            MAX_RUNNERS_PER_MACHINE=${var.runners_per_machine}
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
