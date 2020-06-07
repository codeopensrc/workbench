variable "servers" {}

variable "role" {}
variable "region" {}

variable "aws_bot_access_key" {}
variable "aws_bot_secret_key" {}

variable "datacenter_has_admin" { default = "" }

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

            docker-machine create --driver generic --generic-ip-address=${element(var.public_ips, count.index)} \
            --generic-ssh-key ~/.ssh/id_rsa --engine-install-url "${var.docker_engine_install_url}" \
            ${element(var.names, count.index)}

            docker-machine provision ${element(var.names, count.index)}
        EOF
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

resource "null_resource" "consul_install" {
    count = var.servers
    depends_on = [
        null_resource.docker_init,
        null_resource.docker_leader,
        null_resource.docker_web,
        null_resource.docker_compose,
        null_resource.update_aws
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
            "mkdir -p /etc/consul.d",
        ]
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
        null_resource.consul_install
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
        null_resource.consul_install
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
        null_resource.consul_install
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
        null_resource.consul_file_admin
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
    }


    provisioner "file" {

        # Loop/Depend on admin being bootstrapped before leaving here
        content = <<-EOF

            mkdir -p /etc/consul.d/conf.d
            systemctl start consul.service
            systemctl enable consul.service
            service sshd restart
            sleep 10

            check_consul_status() {
                LAST_CMD=$(consul reload);

                if [ $? -eq 0 ]; then
                    echo "Consul online";
                    exit 0;
                else
                    echo "Restarting consul and waiting another 30s for bootstrapped consul server";
                    systemctl start consul.service
                    sleep 30;
                    check_consul_status
                fi
            }

            check_consul_status

        EOF
        destination = "/tmp/startconsul.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/startconsul.sh",
            "/tmp/startconsul.sh",
        ]
    }

    connection {
        host = element(var.public_ips, count.index)
        type = "ssh"
    }

}

output "output" {
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
        null_resource.consul_service,
    ]
    value = null_resource.consul_service.*.id
}
