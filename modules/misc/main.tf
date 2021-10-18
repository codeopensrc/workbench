variable "servers" {}

variable "region" {}
variable "do_spaces_region" { default = "" }
variable "do_spaces_access_key" { default = "" }
variable "do_spaces_secret_key" { default = "" }

variable "aws_bot_access_key" {}
variable "aws_bot_secret_key" {}

variable "datacenter_has_admin" { default = "" }
variable "s3alias" {}
variable "s3bucket" {}
variable "use_gpg" { default = false }
variable "bot_gpg_name" { default = "" }
variable "bot_gpg_passphrase" { default = "" }
variable "tmp_pubkeylist" { default = "pubkeylist.asc" }

variable "admin_servers" { default = "" }
variable "admin_names" {}
variable "admin_public_ips" {}
variable "admin_private_ips" {}
variable "consul_admin_adv_addresses" {}

variable "lead_servers" { default = "" }
variable "lead_names" {}
variable "lead_public_ips" {}
variable "lead_private_ips" {}
variable "consul_lead_adv_addresses" {}

variable "build_servers" { default = "" }
variable "build_names" {}
variable "build_public_ips" {}
variable "build_private_ips" {}
variable "consul_build_adv_addresses" {}

variable "db_servers" { default = "" }
variable "db_names" {}
variable "db_public_ips" {}
variable "db_private_ips" {}
variable "consul_db_adv_addresses" {}

variable "is_only_leader_count" { default = 0 }
variable "is_only_db_count" { default = 0 }
variable "is_only_build_count" { default = 0 }

variable "consul_lan_leader_ip" { default = "" }
variable "consul_wan_leader_ip" { default = "" }

resource "null_resource" "docker_leader" {
    count = var.lead_servers

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
            CUR_MACHINE_IP=${element(distinct(concat(var.lead_public_ips)), count.index)}
            PREV_MACHINE_IP=${element(distinct(concat(var.lead_public_ips)), count.index == 0 ? 0 : count.index - 1)}

            ssh-keyscan -H $CUR_MACHINE_IP >> ~/.ssh/known_hosts
            CUR_SWARM_VER=$(ssh root@$CUR_MACHINE_IP "docker -v;")
            PREV_SWARM_VER=$(ssh root@$PREV_MACHINE_IP "docker -v;")
            JOINED_SWARM=false

            if [ "$CUR_SWARM_VER" = "$PREV_SWARM_VER" ] && [ "$CUR_MACHINE_IP" != "$PREV_MACHINE_IP" ]; then
                SLEEP_FOR=$((5 + $((${count.index} * 6)) ))
                echo "JOIN_LEADER IN $SLEEP_FOR"
                sleep $SLEEP_FOR
                JOIN_CMD=$(ssh root@$PREV_MACHINE_IP "docker swarm join-token manager | grep -- --token;")
                ssh root@$CUR_MACHINE_IP "set -e; $JOIN_CMD"
                JOINED_SWARM=true
            fi

            # Pretty much we're the newest kid on the block with a different docker version
            if [ "$JOINED_SWARM" = "false" ] || [ ${length(var.lead_names)} -eq 1 ]; then
                echo "START NEW SWARM"
                # TODO: Check if we're already part of a (or our own) swarm
                ssh root@$CUR_MACHINE_IP 'docker swarm init --advertise-addr ${element(var.lead_public_ips, count.index)}:2377' || exit 0
            fi

            DOWN_MACHINES=$(ssh root@$CUR_MACHINE_IP "docker node ls | grep 'Down' | cut -d ' ' -f1;")
            # We might have to loop here if there are 2+ down machines, not sure what happens
            ssh root@$CUR_MACHINE_IP "docker node rm --force $DOWN_MACHINES || exit 0;"
            ssh root@$CUR_MACHINE_IP "docker node update --label-add dc=${var.region} --label-add name=${element(var.lead_names, count.index)} ${element(var.lead_names, count.index)}"

            exit 0
        EOF
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


resource "null_resource" "update_s3" {
    count = length(var.servers)
    depends_on = [
        null_resource.docker_leader,
    ]

    provisioner "file" {
        content = <<-EOF
            [default]
            aws_access_key_id = ${var.aws_bot_access_key}
            aws_secret_access_key = ${var.aws_bot_secret_key}
        EOF
        destination = "/root/.aws/credentials"
    }

    provisioner "remote-exec" {
        inline = [
            (var.aws_bot_access_key != "" ? "mc alias set s3 https://s3.amazonaws.com ${var.aws_bot_access_key} ${var.aws_bot_secret_key}" : "echo 0;"),
            (var.do_spaces_access_key != "" ? "mc alias set spaces https://${var.do_spaces_region}.digitaloceanspaces.com ${var.do_spaces_access_key} ${var.do_spaces_secret_key}" : "echo 0;"),
        ]
    }

    connection {
        host = element(distinct(concat(var.admin_public_ips, var.lead_public_ips, var.db_public_ips, var.build_public_ips)), count.index)
        type = "ssh"
    }
}

# TODO: Turn these seperate consul file resources into one resource
resource "null_resource" "consul_file_admin" {
    count = var.admin_servers
    depends_on = [
        null_resource.docker_leader,
        null_resource.update_s3,
    ]

    provisioner "remote-exec" {
        inline = ["rm -rf /tmp/consul"]
    }
    provisioner "file" {
        #NOTE: bootstrap_expect should be at most 1 per DATACENTER OR BAD STUFF HAPPENS
        content = <<-EOF
            {
                "bootstrap": true,
                "ui_config": {
                    "enabled": true
                },
                "datacenter": "${var.region}",
                "bind_addr": "${element(var.admin_private_ips, count.index)}",
                "client_addr": "0.0.0.0",
                "data_dir": "/tmp/consul",
                "log_level": "INFO",
                "node_name": "${element(var.admin_names, count.index)}",
                "server": true,
                "translate_wan_addrs": true,
                "advertise_addr_wan": "${element(var.consul_admin_adv_addresses, count.index)}",
                "advertise_addr": "${element(var.consul_admin_adv_addresses, count.index)}",
                "enable_local_script_checks": true,
                "reconnect_timeout": "12h",
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
        host = element(var.admin_public_ips, count.index)
        type = "ssh"
    }
}

resource "null_resource" "consul_file_leader" {
    # Any leader ips that are not also an admin ip
    count = var.is_only_leader_count
    depends_on = [
        null_resource.docker_leader,
        null_resource.update_s3,
    ]

    provisioner "file" {
        # NOTE: bootstrap_expect should be at most 1 per DATACENTER OR BAD STUFF HAPPENS
        # TODO: Review if if joining the wan is enough or do we need to bootstrap in each dc
        # ${count.index == 0 && !var.datacenter_has_admin ? "bootstrap_expect: 1," : ""}
        content = <<-EOF
            {
                "bootstrap": ${!var.datacenter_has_admin},
                "ui_config": {
                    "enabled": ${!var.datacenter_has_admin}
                },
                "retry_join_wan": [ "${var.consul_wan_leader_ip}" ],
                "datacenter": "${var.region}",
                "bind_addr": "${tolist(setsubtract(var.lead_private_ips, var.admin_private_ips))[count.index]}",
                "client_addr": "0.0.0.0",
                "data_dir": "/tmp/consul",
                "log_level": "INFO",
                "node_name": "${tolist(setsubtract(var.lead_names, var.admin_names))[count.index]}",
                "server": true,
                "translate_wan_addrs": true,
                "advertise_addr_wan": "${tolist(setsubtract(var.consul_lead_adv_addresses, var.consul_admin_adv_addresses))[count.index]}",
                "advertise_addr": "${tolist(setsubtract(var.consul_lead_adv_addresses, var.consul_admin_adv_addresses))[count.index]}",
                "retry_join": [ "${var.consul_lan_leader_ip}" ],
                "enable_local_script_checks": true,
                "reconnect_timeout": "12h",
                "autopilot": {
                    "cleanup_dead_servers": true,
                    "last_contact_threshold": "5s",
                    "max_trailing_logs": 250,
                    "server_stabilization_time": "10s"
                }
            }
        EOF
        # "advertise_addr_wan": "${element(var.consul_lead_adv_addresses, count.index)}",
        # "advertise_addr": "${element(var.consul_lead_adv_addresses, count.index)}",
        destination = "/etc/consul.d/consul.json"
        connection {
            host = tolist(setsubtract(var.lead_public_ips, var.admin_public_ips))[count.index]
            type = "ssh"
        }
    }
}

resource "null_resource" "consul_file" {
    # Any db ips that are not also leader ips or admin ips
    count = var.is_only_db_count
    depends_on = [
        null_resource.docker_leader,
        null_resource.update_s3,
    ]

    provisioner "file" {
        content = <<-EOF
            {
                "datacenter": "${var.region}",
                "bind_addr": "${tolist(setsubtract(setsubtract(var.db_private_ips, var.lead_private_ips), var.admin_private_ips))[count.index]}",
                "client_addr": "0.0.0.0",
                "data_dir": "/tmp/consul",
                "log_level": "INFO",
                "node_name": "${tolist(setsubtract(setsubtract(var.db_names, var.lead_names), var.admin_names))[count.index]}",
                "server": ${ length(regexall("db", element(var.db_names, count.index))) > 0 ? true : false},
                "translate_wan_addrs": true,
                "advertise_addr_wan": "${tolist(setsubtract(setsubtract(var.consul_db_adv_addresses, var.consul_lead_adv_addresses), var.consul_admin_adv_addresses))[count.index]}",
                "advertise_addr": "${tolist(setsubtract(setsubtract(var.consul_db_adv_addresses, var.consul_lead_adv_addresses), var.consul_admin_adv_addresses))[count.index]}",
                "retry_join": [ "${var.consul_lan_leader_ip}" ],
                "enable_local_script_checks": true,
                ${ length(regexall("db", element(var.db_names, count.index))) > 0 ? "" : "'advertise_reconnect_timeout': '8h'," }
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
            host = tolist(setsubtract(setsubtract(var.db_public_ips, var.lead_public_ips), var.admin_public_ips))[count.index]
            type = "ssh"
        }
    }

}

### TODO: TEMPORARY CAUSE IM LAZY
resource "null_resource" "consul_file_build" {
    count = var.is_only_build_count
    depends_on = [
        null_resource.docker_leader,
        null_resource.update_s3,
    ]

    provisioner "file" {
        content = <<-EOF
            {
                "datacenter": "${var.region}",
                "bind_addr": "${element(var.build_private_ips, count.index)}",
                "client_addr": "0.0.0.0",
                "data_dir": "/tmp/consul",
                "log_level": "INFO",
                "node_name": "${element(var.build_names, count.index)}",
                "server": false,
                "translate_wan_addrs": true,
                "advertise_addr_wan": "${element(var.consul_build_adv_addresses, count.index)}",
                "advertise_addr": "${element(var.consul_build_adv_addresses, count.index)}",
                "retry_join": [ "${var.consul_lan_leader_ip}" ],
                "enable_local_script_checks": true,
                "advertise_reconnect_timeout": "12h",
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
            host = element(var.build_public_ips, count.index)
            type = "ssh"
        }
    }

}

resource "null_resource" "consul_service" {
    count = length(var.servers)
    depends_on = [
        null_resource.docker_leader,
        null_resource.update_s3,
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
        host = element(distinct(concat(var.admin_public_ips, var.lead_public_ips, var.db_public_ips, var.build_public_ips)), count.index)
        type = "ssh"
    }

}

resource "null_resource" "gpg_download" {
    count = var.use_gpg ? 1 : 0
    depends_on = [
        null_resource.docker_leader,
        null_resource.update_s3,
        null_resource.consul_file_leader,
        null_resource.consul_file,
        null_resource.consul_file_admin,
        null_resource.consul_service
    ]

    triggers = {
        ## TODO: Better determine triggers
        ## TODO: Better determine machines that require it
        num_machines_require_gpg = sum([var.admin_servers, var.is_only_db_count])
    }

    ### Download encrypted gpg key on remote server
    provisioner "remote-exec" {
        inline = [ 
            "/usr/local/bin/mc cp ${var.s3alias}/${var.s3bucket}/${var.bot_gpg_name}.asc.gpg $HOME/${var.bot_gpg_name}.asc.gpg"
        ]
    }

    provisioner "local-exec" {
        command = <<-EOF
            ### Copy from remote server to local machine
            IP=${element(distinct(concat(var.admin_public_ips, var.db_public_ips)), count.index)}
            scp root@$IP:~/${var.bot_gpg_name}.asc.gpg .

            ### Prompt user to decrypt file using command to continue, loop X times until done or exit

            check_for_keyfile() {
                if [ -f "${var.bot_gpg_name}.asc" ]; then
                    echo "Found decrypted keyfile, continuing";
                    exit 0;
                else
                    echo "==================================================================="
                    echo "==================================================================="
                    echo "Decrypted unattended key not found."
                    echo "In order to prevent an automated prompt for gpg passphase during apply and instead be a conscious action,"
                    echo "    please decrypt the file and place at it the location specified in config."
                    echo "Both local encrypted and decrypted files will be deleted upon successful upload to the server(s)."
                    echo "Current expected keyfile name is ${var.bot_gpg_name}.asc"
                    echo "Command to run from the correct env directory should roughly be:"
                    echo " gpg --decrypt ${var.bot_gpg_name}.asc.gpg > ${var.bot_gpg_name}.asc"
                    echo "==================================================================="
                    echo "==================================================================="
                    echo "Checking again in 40 seconds"

                    sleep 40;
                    check_for_keyfile
                fi
            }

            check_for_keyfile
        EOF
    }
    provisioner "remote-exec" {
        inline = [ "rm $HOME/${var.bot_gpg_name}.asc.gpg" ]
    }

    connection {
        host = element(distinct(concat(var.admin_public_ips, var.db_public_ips)), count.index)
        type = "ssh"
    }
}

resource "null_resource" "gpg_upload" {
    ## Only admin and DB should need it atm
    count = var.use_gpg ? sum([var.admin_servers, var.is_only_db_count]) : 0
    depends_on = [
        null_resource.docker_leader,
        null_resource.update_s3,
        null_resource.consul_file_leader,
        null_resource.consul_file,
        null_resource.consul_file_admin,
        null_resource.consul_service,
        null_resource.gpg_download
    ]
    provisioner "file" {
        source = "${var.bot_gpg_name}.asc"
        destination = "~/${var.bot_gpg_name}.asc"
    }
    provisioner "file" {
        content = var.bot_gpg_passphrase
        destination = "~/${var.bot_gpg_name}"
    }
    provisioner "remote-exec" {
        inline = [
            <<-EOF
                ### Temporarily using remote pubkeys as recipients
                /usr/local/bin/mc cp ${var.s3alias}/${var.s3bucket}/${var.tmp_pubkeylist} $HOME/${var.tmp_pubkeylist}
                gpg --import --batch $HOME/${var.tmp_pubkeylist}

                gpg --import --batch ~/${var.bot_gpg_name}.asc
                gpg --list-keys | sed -r -n "s/ +([0-9A-H]{10,})/\1:6:/p" | gpg --import-ownertrust
                rm ~/${var.bot_gpg_name}.asc
                rm ~/${var.tmp_pubkeylist}
            EOF
        ]
    }
    connection {
        host = element(distinct(concat(var.admin_public_ips, var.db_public_ips)), count.index)
        type = "ssh"
    }
}

resource "null_resource" "gpg_clean_files" {
    count = var.use_gpg ? 1 : 0
    depends_on = [
        null_resource.docker_leader,
        null_resource.update_s3,
        null_resource.consul_file_leader,
        null_resource.consul_file,
        null_resource.consul_file_admin,
        null_resource.consul_service,
        null_resource.gpg_download,
        null_resource.gpg_upload
    ]
    triggers = {
        ## TODO: Better determine triggers
        ## TODO: Better determine machines that require it
        num_machines_require_gpg = sum([var.admin_servers, var.is_only_db_count])
    }
    provisioner "local-exec" {
        command = <<-EOF
            echo "Removing local keyfiles"
            rm ${var.bot_gpg_name}.asc
            rm ${var.bot_gpg_name}.asc.gpg
        EOF
    }
}

output "output" {
    depends_on = [
        null_resource.docker_leader,
        null_resource.update_s3,
        null_resource.consul_file_leader,
        null_resource.consul_file,
        null_resource.consul_file_admin,
        null_resource.consul_service,
        null_resource.gpg_download,
        null_resource.gpg_upload,
        null_resource.gpg_clean_files
    ]
    value = null_resource.consul_service.*.id
}
