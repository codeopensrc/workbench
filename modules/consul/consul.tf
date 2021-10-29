variable "region" {}
variable "consul_lan_leader_ip" { default = "" }
variable "consul_wan_leader_ip" { default = "" }
variable "datacenter_has_admin" { default = "" }

variable "role" { default = "" }
variable "name" {}
variable "public_ip" {}
variable "private_ip" {}

### TODO: Consolidate down to single templated file adjusting directives based on role

resource "null_resource" "consul_file_admin" {
    count = var.role == "admin" ? 1 : 0

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
                "bind_addr": "${var.private_ip}",
                "client_addr": "0.0.0.0",
                "data_dir": "/tmp/consul",
                "log_level": "INFO",
                "node_name": "${var.name}",
                "server": true,
                "translate_wan_addrs": true,
                "advertise_addr_wan": "${var.private_ip}",
                "advertise_addr": "${var.private_ip}",
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
        host = var.public_ip
        type = "ssh"
    }
}

resource "null_resource" "consul_file_leader" {
    count = var.role == "lead" ? 1 : 0

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
                "bind_addr": "${var.private_ip}",
                "client_addr": "0.0.0.0",
                "data_dir": "/tmp/consul",
                "log_level": "INFO",
                "node_name": "${var.name}",
                "server": true,
                "translate_wan_addrs": true,
                "advertise_addr_wan": "${var.private_ip}",
                "advertise_addr": "${var.private_ip}",
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
        # "advertise_addr_wan": "${element(var.consul_lead_private_ipes, count.index)}",
        # "advertise_addr": "${element(var.consul_lead_private_ipes, count.index)}",
        destination = "/etc/consul.d/consul.json"
        connection {
            host = var.public_ip
            type = "ssh"
        }
    }
}

resource "null_resource" "consul_file" {
    count = var.role == "db" || var.role == "build" ? 1 : 0

    provisioner "file" {
        content = <<-EOF
            {
                "datacenter": "${var.region}",
                "bind_addr": "${var.private_ip}",
                "client_addr": "0.0.0.0",
                "data_dir": "/tmp/consul",
                "log_level": "INFO",
                "node_name": "${var.name}",
                "server": ${ length(regexall("db", var.name)) > 0 ? true : false},
                "translate_wan_addrs": true,
                "advertise_addr_wan": "${var.private_ip}",
                "advertise_addr": "${var.private_ip}",
                "retry_join": [ "${var.consul_lan_leader_ip}" ],
                "enable_local_script_checks": true,
                ${ length(regexall("db", var.name)) > 0 ? "" : "\"advertise_reconnect_timeout\": \"8h\"," }
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
            host = var.public_ip
            type = "ssh"
        }
    }

}


resource "null_resource" "consul_service" {
    depends_on = [
        null_resource.consul_file_admin,
        null_resource.consul_file_leader,
        null_resource.consul_file
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
        host = var.public_ip
        type = "ssh"
    }

}
