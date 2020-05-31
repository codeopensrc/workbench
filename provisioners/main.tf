variable "servers" {}

variable "role" {}
variable "region" {}

variable "aws_bot_access_key" {}
variable "aws_bot_secret_key" {}

variable "known_hosts" { default = [] }
variable "active_env_provider" { default = "" }
variable "root_domain_name" { default = "" }
variable "deploy_key_location" {}
variable "chef_local_dir" {}

variable "leader_hostname_ready" { default = "" }
variable "admin_hostname_ready" { default = "" }
variable "db_hostname_ready" { default = "" }

variable "chef_server_ready" { default = "" }
variable "chef_client_ver" { default = "" }
variable "datacenter_has_admin" { default = "" }

variable "pg_read_only_pw" { default = "" }
variable "db_backups_enabled" { default = false }
variable "run_service_enabled" { default = false }
variable "send_logs_enabled" { default = false }
variable "send_jsons_enabled" { default = false }

variable "names" {
    type = list(string)
    default = []
}
variable "public_ips" {
    type = list(string)
    default = []
}
variable "private_ips" {
    type = list(string)
    default = []
}
variable "consul_adv_addresses" {
    type = list(string)
    default = []
}

variable "docker_leader_name" { default = "" }

variable "consul_lan_leader_ip" { default = "" }
variable "consul_wan_leader_ip" { default = "" }

variable "join_machine_id" { default = "" }

variable "consul_version" { default = "" }
variable "docker_compose_version" { default = "" }
variable "docker_engine_install_url" { default = "" }
# TODO: Implement base docker engine url with or without docker_engine_version built in
# variable "docker_engine_install_url" { default = "https://docs.DOMAIN/download/docker-" }

variable "joinSwarm" { default = false }
variable "installCompose" { default = false }

# UPD: 11/5/19 - Using DOMAIN as the engine install url was causing issues resolving the domain
#   as the newly booted servers sometimes dont resolve to certain domains/ip addresses.
resource "null_resource" "docker_init" {
    count = var.servers

    # https://github.com/docker/machine/issues/3039
    # docker-machine provision

    provisioner "local-exec" {
        command = "docker-machine rm ${element(var.names, count.index)} -y; exit 0"
    }

    provisioner "local-exec" {
        # We aren't sure if we need the api token, taking out for now - we thought
        #   we were hitting some unathenticated api limit according to docker
        # --github-api-token=
        # "https://get.docker.com"    Dockers default engine install url
        # "https://releases.rancher.com/install-docker/${var.docker_engine_version}"    To download specific version
        command = <<-EOF
            echo ${var.leader_hostname_ready}
            echo ${var.admin_hostname_ready}
            echo ${var.db_hostname_ready}

            docker-machine create --driver generic --generic-ip-address=${element(var.public_ips, count.index)} \
            --generic-ssh-key ~/.ssh/id_rsa --engine-install-url "${var.docker_engine_install_url}" \
            ${element(var.names, count.index)}

            docker-machine provision ${element(var.names, count.index)}
        EOF
    }
}


resource "null_resource" "provision_init" {
    count = var.servers
    depends_on = [null_resource.docker_init]

    provisioner "file" {
        content = <<-EOF
            [credential]
                helper = store
        EOF
        destination = "/root/.gitconfig"
    }

    provisioner "file" {
        source = "${path.module}/template_files/tmux.conf"
        destination = "/root/.tmux.conf"
    }

    provisioner "remote-exec" {
        inline = [
            "sudo apt-get update",
            "sudo apt-get install build-essential apt-utils openjdk-8-jdk vim git awscli -y",
            "mkdir -p /root/repos",
            "mkdir -p /root/builds",
            "mkdir -p /root/code",
            "mkdir -p /root/code/logs",
            "mkdir -p /root/code/backups",
            "mkdir -p /root/code/scripts",
            "mkdir -p /root/.tmux/plugins",
            "mkdir -p /root/.ssh",
            "(cd /root/.ssh && ssh-keygen -f id_rsa -t rsa -N '')",
            "git clone https://github.com/tmux-plugins/tpm /root/.tmux/plugins/tpm",
            "cat /usr/share/zoneinfo/America/Los_Angeles > /etc/localtime",
            "timedatectl set-timezone 'America/Los_Angeles'",
        ]
        # TODO: Configurable timezone
    }

    connection {
        host = element(var.public_ips, count.index)
        type = "ssh"
    }

}

resource "null_resource" "temp_whitelist" {
    count = var.servers
    depends_on = [null_resource.docker_init]

    provisioner "remote-exec" {
        inline = [ "mkdir -p /root/code/access" ]
    }

    provisioner "file" {
        content = fileexists("${path.module}/template_files/ignore/authorized_keys") ? file("${path.module}/template_files/ignore/authorized_keys") : ""
        destination = "/root/.ssh/authorized_keys"
    }

    connection {
        host = element(var.public_ips, count.index)
        type = "ssh"
    }
}

resource "null_resource" "docker_leader" {
    count      = var.joinSwarm && var.role == "manager" ? var.servers : 0
    depends_on = [null_resource.docker_init]

    # Create a docker swarm
    provisioner "local-exec" {
        # Uses sh
        # TODO: Since we're using scripts for replacing servers... might as well turn this into one
        #   when we finally extract provisioners in an intelligent way instead of this single file mess
        # TODO: We either need a consul kv lookup for other docker swarms of the same version or figure out a good way
        #   to look up and down the line of docker-machines to find an appropriate swarm to join
        command = <<-EOF
            # Not the most ideal solution, but it will cover 70-95% of use cases until
            #   we setup a consul KV store for docker swarm versions and their tokens
            CUR_MACHINE_NAME=${element(var.names, count.index)}
            FIND_MACHINE_NAME=${replace(element(var.names, count.index), substr(element(var.names, count.index), -4, -1), var.join_machine_id)}
            PREV_MACHINE_NAME=${element(var.names, count.index == 0 ? 0 : count.index - 1)}

            CUR_SWARM_VER=$(docker-machine ssh $CUR_MACHINE_NAME "docker -v;")
            JOINED_SWARM=false

            # First try the specified num machine
            if [ ! -z ${var.join_machine_id} ]; then
                FIND_SWARM_VER=$(docker-machine ssh $FIND_MACHINE_NAME "docker -v;")

                if [ "$CUR_SWARM_VER" = "$FIND_SWARM_VER" ] && [  "$CUR_MACHINE_NAME" != "$FIND_MACHINE_NAME" ]; then
                    # Works for lower numbers, need something better than index * fixed amount
                    SLEEP_FOR=$((5 + $((${count.index} * 6)) ))
                    echo "JOIN_LEADER IN $SLEEP_FOR"
                    sleep $SLEEP_FOR
                    JOIN_CMD=$(docker-machine ssh $FIND_MACHINE_NAME "docker swarm join-token manager | grep -- --token;")
                    docker-machine ssh $CUR_MACHINE_NAME "set -e; $JOIN_CMD"
                    JOINED_SWARM=true
                fi
            fi

            # If we didnt provide a number or they were the same machine or different versions, try
            #   the one at index - 1
            if [ ! -z "$PREV_MACHINE_NAME" ] && [ "$JOINED_SWARM" = "false" ]; then
                PREV_SWARM_VER=$(docker-machine ssh $PREV_MACHINE_NAME "docker -v;")

                if [ "$CUR_SWARM_VER" = "$PREV_SWARM_VER" ] && [ "$CUR_MACHINE_NAME" != "$PREV_MACHINE_NAME" ]; then
                    SLEEP_FOR=$((5 + $((${count.index} * 6)) ))
                    echo "JOIN_LEADER IN $SLEEP_FOR"
                    sleep $SLEEP_FOR
                    JOIN_CMD=$(docker-machine ssh $PREV_MACHINE_NAME "docker swarm join-token manager | grep -- --token;")
                    docker-machine ssh $CUR_MACHINE_NAME "set -e; $JOIN_CMD"
                    JOINED_SWARM=true
                fi
            fi

            # Pretty much we're the newest kid on the block with a different docker version
            if [ "$JOINED_SWARM" = "false" ] || [ ${length(var.names)} -eq 1 ]; then
                echo "START NEW SWARM"
                docker-machine ssh $CUR_MACHINE_NAME 'docker swarm init --advertise-addr ${element(var.public_ips, count.index)}:2377'
            fi

            DOWN_MACHINES=$(docker-machine ssh $CUR_MACHINE_NAME "docker node ls | grep 'Down' | cut -d ' ' -f1;")
            # We might have to loop here if there are 2+ down machines, not sure what happens
            docker-machine ssh $CUR_MACHINE_NAME "docker node rm --force $DOWN_MACHINES; exit 0;"
            docker-machine ssh $CUR_MACHINE_NAME "docker node update --label-add dc=${var.region} --label-add name=${element(var.names, count.index)} ${element(var.names, count.index)}"
        EOF
    }
}

# We haven't fully tested/tuned web servers just yet, only leader servers
resource "null_resource" "docker_web" {
    count      = var.joinSwarm && var.role == "web" ? var.servers : 0
    depends_on = [null_resource.docker_init]

    # Join a docker swarm
    provisioner "local-exec" {
        # TODO: We dont use web instances yet, but we should ensure that web instances joining the leaders/cluster ALSO
        #   share the same docker version so we dont introduce swarm/load balancing/proxy bugs, like in docker_leader resource
        # SWARM_DOCKER_VER=$(docker-machine ssh ${element(var.names, 1)} "docker -v;")
        # CUR_DOCKER_VER=$(docker-machine ssh ${element(var.names, count.index)} "docker -v;")

        command = <<-EOF
            JOIN_CMD=$(docker-machine ssh ${var.docker_leader_name} "docker swarm join-token worker | grep -- --token;");
            docker-machine ssh ${element(var.names, count.index)} "set -e; $JOIN_CMD;"

            OLD_ID=$(docker-machine ssh ${var.docker_leader_name} "docker node ls --filter name=${element(var.names, count.index)} | grep Down | cut -d ' ' -f1;")
            docker-machine ssh ${var.docker_leader_name} "docker node rm --force $OLD_ID;"
            docker-machine ssh ${var.docker_leader_name} "docker node update --label-add dc=${var.region} --label-add name=${element(var.names, count.index)} ${element(var.names, count.index)}"
        EOF
    }
}

resource "null_resource" "docker_compose" {
    count = var.installCompose ? var.servers : 0
    depends_on = [
        null_resource.docker_init,
        null_resource.docker_leader,
        null_resource.docker_web,
    ]

    provisioner "remote-exec" {
        inline = [
            "curl -L https://github.com/docker/compose/releases/download/${var.docker_compose_version}/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose",
            "chmod +x /usr/local/bin/docker-compose"
        ]
        connection {
            host = element(var.public_ips, count.index)
            type = "ssh"
        }
    }
}

resource "null_resource" "update_aws" {
    count = var.servers
    depends_on = [
        null_resource.docker_init,
        null_resource.docker_leader,
        null_resource.docker_web,
        null_resource.docker_compose,
        null_resource.provision_init,
    ]

    provisioner "remote-exec" {
        inline = [
            "curl -O https://bootstrap.pypa.io/get-pip.py",
            "python3 get-pip.py",
            "pip3 install awscli --upgrade",
            "mkdir -p /root/.aws"
        ]
    }

    provisioner "file" {
        content = <<-EOF
            [default]
            aws_access_key_id = ${var.aws_bot_access_key}
            aws_secret_access_key = ${var.aws_bot_secret_key}
        EOF
        destination = "/root/.aws/credentials"
    }

    connection {
        host = element(var.public_ips, count.index)
        type = "ssh"
    }
}

# NOTE: We manually install/configure consul over chef as the chef cookbook was outdated
#  and we don't have sufficient knowledge how to create a "proper" one just yet
resource "null_resource" "consul_install" {
    count = var.servers
    depends_on = [
        null_resource.docker_init,
        null_resource.docker_leader,
        null_resource.docker_web,
        null_resource.docker_compose,
        null_resource.update_aws,
    ]

    # Install consul
    provisioner "remote-exec" {
        inline = [
            "echo '\nClientAliveInterval 30' >> /etc/ssh/sshd_config",
            "apt-get update",
            "apt-get install unzip git -y",
            "curl https://releases.hashicorp.com/consul/${var.consul_version}/consul_${var.consul_version}_linux_amd64.zip -o ~/consul.zip",
            "unzip ~/consul.zip",
            "rm -rf ~/*.zip",
            "mv ~/consul /usr/local/bin",
            "mkdir -p /etc/consul.d/conf.d",
            "mkdir -p /etc/consul.d/templates"
        ]
    }

    provisioner "file" {
        content = file("${path.module}/template_files/checks/dns.json")
        destination = "/etc/consul.d/conf.d/dns.json"
    }

    provisioner "remote-exec" {
        inline = [ "chmod 0755 /etc/consul.d/conf.d/dns.json" ]
    }

    connection {
        host = element(var.public_ips, count.index)
        type = "ssh"
    }
}

resource "null_resource" "consul_file_admin" {
    count = var.role == "admin" ? var.servers : 0
    depends_on = [
        null_resource.docker_init,
        null_resource.docker_leader,
        null_resource.docker_web,
        null_resource.docker_compose,
        null_resource.update_aws,
        null_resource.consul_install,
    ]

    provisioner "remote-exec" {
        inline = ["rm -rf /tmp/consul"]
    }
    provisioner "file" {
        #NOTE: bootstrap_expect should be at most 1 per DATACENTER OR BAD STUFF HAPPENS
        content = <<-EOF
            {
                "bootstrap": true,
                "datacenter": "${var.region}",
                "bind_addr": "${element(var.private_ips, count.index)}",
                "client_addr": "0.0.0.0",
                "data_dir": "/tmp/consul",
                "log_level": "INFO",
                "node_name": "${element(var.names, count.index)}",
                "server": true,
                "ui": true,
                "translate_wan_addrs": true,
                "advertise_addr_wan": "${element(var.consul_adv_addresses, count.index)}",
                "advertise_addr": "${element(var.consul_adv_addresses, count.index)}",
                "enable_script_checks": true,
                "autopilot": {
                    "cleanup_dead_servers": true,
                    "last_contact_threshold": "5s",
                    "max_trailing_logs": 250,
                    "server_stabilization_time": "10s"
                }
            }
        EOF
        destination = "/etc/consul.d/consul.json"
    }
    connection {
        host = element(var.public_ips, count.index)
        type = "ssh"
    }
}

resource "null_resource" "consul_file_leader" {
    count = var.role == "manager" ? var.servers : 0
    depends_on = [
        null_resource.docker_init,
        null_resource.docker_leader,
        null_resource.docker_web,
        null_resource.docker_compose,
        null_resource.update_aws,
        null_resource.consul_install,
    ]

    provisioner "file" {
        # NOTE: bootstrap_expect should be at most 1 per DATACENTER OR BAD STUFF HAPPENS
        # TODO: Review if if joining the wan is enough or do we need to bootstrap in each dc
        # ${count.index == 0 && !var.datacenter_has_admin ? "bootstrap_expect: 1," : ""}
        content = <<-EOF
            {
                ${var.consul_wan_leader_ip != "" ? "\"retry_join_wan\": [ \"var.consul_wan_leader_ip\" ]," : ""}
                "datacenter": "${var.region}",
                "bind_addr": "${element(var.private_ips, count.index)}",
                "client_addr": "0.0.0.0",
                "data_dir": "/tmp/consul",
                "log_level": "INFO",
                "node_name": "${element(var.names, count.index)}",
                "server": true,
                "translate_wan_addrs": true,
                "advertise_addr_wan": "${element(var.consul_adv_addresses, count.index)}",
                "advertise_addr": "${element(var.consul_adv_addresses, count.index)}",
                "retry_join": [ "${var.consul_lan_leader_ip}" ],
                "enable_script_checks": true,
                "autopilot": {
                    "cleanup_dead_servers": true,
                    "last_contact_threshold": "5s",
                    "max_trailing_logs": 250,
                    "server_stabilization_time": "10s"
                }
            }
        EOF
        destination = "/etc/consul.d/consul.json"
        connection {
            host = element(var.public_ips, count.index)
            type = "ssh"
        }
    }
}

resource "null_resource" "consul_file" {
    count = var.role == "manager" || var.role == "admin" ? 0 : var.servers
    depends_on = [
        null_resource.docker_init,
        null_resource.docker_leader,
        null_resource.docker_web,
        null_resource.docker_compose,
        null_resource.update_aws,
        null_resource.consul_install,
    ]

    provisioner "file" {
        content = <<-EOF
            {
                "datacenter": "${var.region}",
                "bind_addr": "${element(var.private_ips, count.index)}",
                "client_addr": "0.0.0.0",
                "data_dir": "/tmp/consul",
                "log_level": "INFO",
                "node_name": "${element(var.names, count.index)}",
                "server": ${var.role == "db" ? true : false},
                "translate_wan_addrs": true,
                "advertise_addr_wan": "${element(var.consul_adv_addresses, count.index)}",
                "advertise_addr": "${element(var.consul_adv_addresses, count.index)}",
                "retry_join": [ "${var.consul_lan_leader_ip}" ],
                "enable_script_checks": true,
                "autopilot": {
                    "cleanup_dead_servers": true,
                    "last_contact_threshold": "5s",
                    "max_trailing_logs": 250,
                    "server_stabilization_time": "10s"
                }
            }
        EOF
        destination = "/etc/consul.d/consul.json"
        connection {
            host = element(var.public_ips, count.index)
            type = "ssh"
        }
    }

}

resource "null_resource" "upload_deploy_key" {
    count = var.servers
    depends_on = [
        null_resource.docker_init,
        null_resource.docker_leader,
        null_resource.docker_web,
        null_resource.docker_compose,
        null_resource.update_aws,
        null_resource.consul_install,
        null_resource.consul_file_leader,
        null_resource.consul_file,
        null_resource.consul_file_admin,
    ]

    provisioner "remote-exec" {
        inline = [
            "rm /root/.ssh/known_hosts",
            "rm /root/.ssh/config",
            "rm /root/.ssh/deploy.key",
            "ls /root/.ssh",
        ]
    }

    provisioner "file" {
        content = templatefile("${path.module}/template_files/sshconfig", {
            fqdn = var.root_domain_name
            known_hosts = [
                for HOST in var.known_hosts:
                HOST.site
                if HOST.site != "gitlab.${var.root_domain_name}"
            ]
        })
        destination = "/root/.ssh/config"
    }

    # NOTE: Populate the known_hosts entry for auxiliary servers AFTER we upload our backed up ssh keys to the admin server
    #  The entry that goes into known hosts is the PUBLIC key of the ssh SERVER found at /etc/ssh/ssh_host_rsa_key.pub
    #  For the sub domain gitlab.ROOTDOMAIN.COM
    provisioner "file" {
        content = templatefile("${path.module}/template_files/known_hosts", {
            known_hosts = var.known_hosts
        })
        destination = "/root/.ssh/known_hosts"
    }

    provisioner "file" {
        content = file("${var.deploy_key_location}")
        destination = "/root/.ssh/deploy.key"
    }

    # TODO: Possibly utilize this to have a useful docker registry variable
    # provisioner "file" {
    #     content = <<-EOF
    #         #!/bin/bash
    #
    #         export DOCKER_REGISTRY=""
    #     EOF
    #     destination = "/root/.bash_aliases"
    # }

    provisioner "remote-exec" {
        inline = ["chmod 0600 /root/.ssh/deploy.key"]
    }

    connection {
        host = element(var.public_ips, count.index)
        type = "ssh"
    }
}

# TODO: This is temporary until we switch over db urls being application specific
resource "null_resource" "upload_consul_dbchecks" {
    count = var.role == "db" ? var.servers : 0
    depends_on = [
        null_resource.docker_init,
        null_resource.docker_leader,
        null_resource.docker_web,
        null_resource.docker_compose,
        null_resource.update_aws,
        null_resource.consul_install,
        null_resource.consul_file_leader,
        null_resource.consul_file,
        null_resource.consul_file_admin,
        null_resource.upload_deploy_key,
    ]

    # TODO: Conditionally only add checks if we're booting up an instance of that DB type
    provisioner "file" {
        content = templatefile("${path.module}/template_files/checks/consul_pg.json", {
            read_only_pw = var.pg_read_only_pw
            datacenter = var.active_env_provider == "digital_ocean" ? "do1" : "aws1"
            fqdn = var.root_domain_name
        })
        destination = "/etc/consul.d/templates/pg.json"
    }

    provisioner "file" {
        content = file("${path.module}/template_files/checks/consul_mongo.json")
        destination = "/etc/consul.d/templates/mongo.json"
    }

    provisioner "file" {
        content = file("${path.module}/template_files/checks/consul_redis.json")
        destination = "/etc/consul.d/templates/redis.json"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod 0755 /etc/consul.d/templates/pg.json",
            "chmod 0755 /etc/consul.d/templates/mongo.json",
            "chmod 0755 /etc/consul.d/templates/redis.json"
        ]
    }

    connection {
        host = element(var.public_ips, count.index)
        type = "ssh"
    }
}

resource "null_resource" "bootstrap" {
    count = var.role == "admin" ? 0 : var.servers
    depends_on = [
        null_resource.docker_init,
        null_resource.docker_leader,
        null_resource.docker_web,
        null_resource.docker_compose,
        null_resource.update_aws,
        null_resource.consul_install,
        null_resource.consul_file_leader,
        null_resource.consul_file,
        null_resource.consul_file_admin,
        null_resource.upload_deploy_key,
        null_resource.upload_consul_dbchecks,
    ]

    provisioner "local-exec" {
        # Cant have this step run until we are sure cookbooks/databags are uploaded - which is the last step
        #   when provisioning the admin server. We use this line to force wait    echo ${var.chef_server_ready}
        command = <<-EOF
            echo ${var.chef_server_ready}
            knife node delete ${element(var.names, count.index)} --config ${var.chef_local_dir}/knife.rb -y;
            knife client delete ${element(var.names, count.index)} --config ${var.chef_local_dir}/knife.rb -y;
            docker-machine ssh ${element(var.names, count.index)} 'sudo rm /etc/chef/client.pem';
            exit 0;
        EOF
    }

    provisioner "local-exec" {
        command = <<-EOF
            ssh-keygen -R ${element(var.public_ips, count.index)};
            ROLE=${var.role == "db" ? var.role : ""}
            if [ -n "$ROLE" ]; then
                knife bootstrap ${element(var.public_ips, count.index)} --sudo \
                    --identity-file ~/.ssh/id_rsa --node-name ${element(var.names, count.index)} \
                    --run-list 'role[${var.role}]' --config ${var.chef_local_dir}/knife.rb --bootstrap-version ${var.chef_client_ver}
            fi
        EOF
    }

    provisioner "file" {
        source = "${path.module}/template_files/scripts/"
        destination = "/root/code/scripts"
    }

    provisioner "file" {
        content = <<-EOF

            DB_BACKUPS_ENABLED=${var.db_backups_enabled}
            RUN_SERVICE=${var.run_service_enabled}
            SEND_LOGS=${var.send_logs_enabled}
            SEND_JSONS=${var.send_jsons_enabled}

            if [ "$DB_BACKUPS_ENABLED" != "true" ]; then
                sed -i 's/BACKUPS_ENABLED=true/BACKUPS_ENABLED=false/g' /root/code/scripts/db/backup*
            fi
            if [ "$RUN_SERVICE" != "true" ]; then
                sed -i 's/RUN_SERVICE=true/RUN_SERVICE=false/g' /root/code/scripts/leader/runService*
            fi
            if [ "$SEND_LOGS" != "true" ]; then
                sed -i 's/SEND_LOGS=true/SEND_LOGS=false/g' /root/code/scripts/leader/sendLog*
            fi
            if [ "$SEND_JSONS" != "true" ]; then
                sed -i 's/SEND_JSONS=true/SEND_JSONS=false/g' /root/code/scripts/leader/sendJsons*
            fi

            exit 0
        EOF
        destination = "/tmp/cronscripts.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/cronscripts.sh",
            "/tmp/cronscripts.sh",
        ]
    }
    connection {
        host = element(var.public_ips, count.index)
        type = "ssh"
    }
}



resource "null_resource" "consul_service" {
    count = var.servers
    depends_on = [
        null_resource.docker_init,
        null_resource.docker_leader,
        null_resource.docker_web,
        null_resource.docker_compose,
        null_resource.update_aws,
        null_resource.consul_install,
        null_resource.consul_file_leader,
        null_resource.consul_file,
        null_resource.consul_file_admin,
        null_resource.upload_deploy_key,
        null_resource.upload_consul_dbchecks,
    ]

    provisioner "file" {
        content = <<-EOF
            [Service]
            ExecStart = /usr/local/bin/consul agent --config-file=/etc/consul.d/consul.json --config-dir=/etc/consul.d/conf.d
            ExecStop = /usr/local/bin/consul leave
            Restart = always

            [Install]
            WantedBy = multi-user.target
        EOF
        destination = "/etc/systemd/system/consul.service"
        connection {
            host = element(var.public_ips, count.index)
            type = "ssh"
        }
    }

    provisioner "remote-exec" {
        inline = [
            "systemctl start consul.service",
            "systemctl enable consul.service",
            "service sshd restart",
            "sleep 10"
        ]
        connection {
            host = element(var.public_ips, count.index)
            type = "ssh"
        }
    }

}

output "end_of_provisioner" {
    depends_on = [
        null_resource.docker_init,
        null_resource.docker_leader,
        null_resource.docker_web,
        null_resource.docker_compose,
        null_resource.update_aws,
        null_resource.consul_install,
        null_resource.consul_file_leader,
        null_resource.consul_file,
        null_resource.consul_file_admin,
        null_resource.upload_deploy_key,
        null_resource.upload_consul_dbchecks,
        null_resource.bootstrap,
        null_resource.consul_service,
    ]
    value = null_resource.consul_service.*.id
}


resource "null_resource" "destroy_chef_node" {
    count      = var.servers
    depends_on = [null_resource.docker_init]

    ####### On Destroy ######
    # TODO: If installing chef never completed, do not run as 'knife node delete' hangs
    # TODO: Add some time of ping/"if server up" command to https://chef.DOMAIN.COM/organizations/ORG/nodes/NODE and if failed, skip
    # curl should work...
    # If having trouble removing on destroy (due to admin being destroyed first), remove the instances from the .tfstate state file
    provisioner "local-exec" {
        # If 301 redirect to https then its up
        when = destroy
        command = <<-EOF
            echo ${var.chef_server_ready}

            SERVER_RES_CODE=$(curl -I "http://chef.${var.root_domain_name}" 2>/dev/null | head -n 1 | cut -d " " -f2)
            if [ -d "${var.chef_local_dir}" ] && [ "$SERVER_RES_CODE" = "301" ]; then
                knife node delete ${element(var.names, count.index)} --config ${var.chef_local_dir}/knife.rb -y;
                knife client delete ${element(var.names, count.index)} --config ${var.chef_local_dir}/knife.rb -y;
            fi
            exit 0;
        EOF
        on_failure = continue
    }
}

# TODO: Need separate destroying mechanisms for admin and leader
resource "null_resource" "destroy" {
    count      = var.servers
    depends_on = [null_resource.docker_init]

    # TODO: Need to trigger these on scaling down but not on a "terraform destroy"
    # Or maybe a seperate paramater to set to run: scaling_down=true, false by default
    # provisioner "file" {
    #     when = destroy
    #     content = <<-EOF
    #         if [ "${var.role == "manager"}" = "true" ]; then
    #             docker node update --availability="drain" ${element(var.names, count.index)}
    #             sleep 20;
    #             docker node demote ${element(var.names, count.index)}
    #             sleep 5
    #         fi
    #     EOF
    #     destination = "/tmp/leave.sh"
    # }
    #
    # ####### On Destroy ######
    # provisioner "remote-exec" {
    #     when = destroy
    #     ## TODO: Review all folders we create/modify on the server and remove them
    #     ##   for no actual reason in particular, just being thorough
    #     inline = [
    #         "chmod +x /tmp/leave.sh",
    #         "/tmp/leave.sh",
    #         "docker swarm leave",
    #         "docker swarm leave --force;",
    #         "systemctl stop consul.service",
    #         "rm -rf /etc/ssl",
    #         "exit 0;"
    #     ]
    #     on_failure = continue
    # }
    #
    # connection {
    #     host    = element(var.public_ips, count.index)
    #     type    = "ssh"
    #     timeout = "45s"
    # }

    # Remove any previous docker-machine references to this name
    provisioner "local-exec" {
        when = destroy
        command = <<-EOF
            docker-machine rm ${element(var.names, count.index)} -y;
            exit 0;
        EOF
        on_failure = continue
    }
}
