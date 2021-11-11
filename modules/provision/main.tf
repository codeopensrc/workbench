
variable "name" { default = "" }
variable "public_ip" { default = "" }
variable "known_hosts" { default = [] }
variable "root_domain_name" { default = "" }
variable "deploy_key_location" {}

variable "private_ip" { default = "" }
variable "pg_read_only_pw" { default = "" }

variable "admin_ip_private" { default = "" }

variable "nodeexporter_version" { default = "" }
variable "promtail_version" { default = "" }
variable "consulexporter_version" { default = "" }


resource "null_resource" "access" {

    provisioner "remote-exec" {
        inline = [
            "rm /root/.ssh/known_hosts",
            "rm /root/.ssh/config",
            "rm /root/.ssh/deploy.key",
            "ls /root/.ssh",
        ]
    }

    provisioner "file" {
        content = templatefile("${path.module}/templatefiles/sshconfig", {
            fqdn = var.root_domain_name
            known_hosts = [
                for HOST in var.known_hosts:
                HOST.site
                if HOST.site != "gitlab.${var.root_domain_name}"
            ]
        })
        destination = "/root/.ssh/config"
    }

    # Place public ssh keys of git repository hosting service in known_hosts, normally available through the provider
    #   See the bitbucket example already in templatefiles/known_hosts
    # If intending to host a gitlab instance. The entry that goes into known_hosts is the PUBLIC key of the ssh SERVER found at /etc/ssh/ssh_host_rsa_key.pub
    #   for your server that hosts the sub domain gitlab.ROOTDOMAIN.COM.
    provisioner "file" {
        content = templatefile("${path.module}/templatefiles/known_hosts", {
            known_hosts = var.known_hosts
        })
        destination = "/root/.ssh/known_hosts"
    }

    # TODO: Determine best way to use identity files and remote repo locations
    provisioner "file" {
        content = file(var.deploy_key_location)
        destination = "/root/.ssh/deploy.key"
    }
    provisioner "remote-exec" {
        inline = ["chmod 0600 /root/.ssh/deploy.key"]
    }

    connection {
        host = var.public_ip
        type = "ssh"
    }
}

resource "null_resource" "reprovision_scripts" {
    depends_on = [
        null_resource.access,
    ]

    provisioner "file" {
        ## TODO: Change this to a "packer_scripts_path" var
        source = "${path.module}/../packer/scripts/"
        destination = "/root/code/scripts"
    }

    connection {
        host = var.public_ip
        type = "ssh"
    }
}

# TODO: This is temporary until we switch over db urls being application specific
resource "null_resource" "consul_checks" {

    depends_on = [
        null_resource.access,
        null_resource.reprovision_scripts,
    ]

    provisioner "remote-exec" {
        inline = [
            "mkdir -p /etc/consul.d/conf.d",
            "mkdir -p /etc/consul.d/templates"
        ]
    }

    provisioner "file" {
        # TODO: Configurable user/pass per DB for a readonly user check
        content = templatefile("${path.module}/templatefiles/checks/consul_pg.json", {
            read_only_pw = var.pg_read_only_pw
            ip_address = var.private_ip
            port = "5432"
            version = "9.5"
        })
        destination = "/etc/consul.d/templates/pg.json"
    }

    provisioner "file" {
        # TODO: Un-hardcode version/port
        content = templatefile("${path.module}/templatefiles/checks/consul_mongo.json", {
            ip_address = var.private_ip
            port = "27017"
            version = "4.4.6"
        })
        destination = "/etc/consul.d/templates/mongo.json"
    }

    provisioner "file" {
        content = templatefile("${path.module}/templatefiles/checks/consul_redis.json", {
            port = "6379"
            version = "5.0.9"
        })
        destination = "/etc/consul.d/templates/redis.json"
    }

    provisioner "file" {
        content = file("${path.module}/templatefiles/checks/dns.json")
        destination = "/etc/consul.d/conf.d/dns.json"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod 0755 /etc/consul.d/templates/pg.json",
            "chmod 0755 /etc/consul.d/templates/mongo.json",
            "chmod 0755 /etc/consul.d/templates/redis.json",
            "chmod 0755 /etc/consul.d/conf.d/dns.json"
        ]
    }

    connection {
        host = var.public_ip
        type = "ssh"
    }
}

resource "null_resource" "exporters" {
    depends_on = [
        null_resource.access,
        null_resource.reprovision_scripts,
        null_resource.consul_checks,
    ]

    provisioner "remote-exec" {
        inline = [
            <<-EOF
                ADMIN_IP=${var.admin_ip_private}
                if [ -z "$ADMIN_IP" ]; then exit 0; fi

                FILENAME1=node_exporter-${var.nodeexporter_version}.linux-amd64.tar.gz
                [ ! -f /tmp/$FILENAME1 ] && wget https://github.com/prometheus/node_exporter/releases/download/v${var.nodeexporter_version}/$FILENAME1 -P /tmp
                tar xvfz /tmp/$FILENAME1 --wildcards --strip-components=1 -C /usr/local/bin */node_exporter

                FILENAME2=promtail-linux-amd64.zip
                [ ! -f /tmp/$FILENAME2 ] && wget https://github.com/grafana/loki/releases/download/v${var.promtail_version}/$FILENAME2 -P /tmp
                unzip /tmp/$FILENAME2 -d /usr/local/bin && chmod a+x /usr/local/bin/promtail*amd64

                FILENAME3=promtail-local-config.yaml
                mkdir -p /etc/promtail.d
                [ ! -f /etc/promtail.d/$FILENAME3 ] && wget https://raw.githubusercontent.com/grafana/loki/main/clients/cmd/promtail/$FILENAME3 -P /etc/promtail.d
                sed -i "s/localhost:/${var.admin_ip_private}:/" /etc/promtail.d/$FILENAME3
                sed -ni '/nodename:/!p; $ a \\      nodename: ${var.name}' /etc/promtail.d/$FILENAME3

                FILENAME4=consul_exporter-${var.consulexporter_version}.linux-amd64.tar.gz
                [ ! -f /tmp/$FILENAME4 ] && wget https://github.com/prometheus/consul_exporter/releases/download/v${var.consulexporter_version}/$FILENAME4 -P /tmp
                tar xvfz /tmp/$FILENAME4 --wildcards --strip-components=1 -C /usr/local/bin */consul_exporter
            EOF
        ]
    }

    provisioner "file" {
        content = templatefile("${path.module}/templatefiles/services/nodeexporter.service", {})
        destination = "/etc/systemd/system/nodeexporter.service"
    }
    provisioner "file" {
        content = templatefile("${path.module}/templatefiles/services/consulexporter.service", {})
        destination = "/etc/systemd/system/consulexporter.service"
    }
    provisioner "file" {
        content = templatefile("${path.module}/templatefiles/services/promtail.service", {})
        destination = "/etc/systemd/system/promtail.service"
    }

    provisioner "remote-exec" {
        inline = [
            <<-EOF
                ADMIN_IP=${var.admin_ip_private}
                if [ -z "$ADMIN_IP" ]; then exit 0; fi

                ${length(regexall("admin", var.name)) > 0 ? "echo" : "sudo systemctl start nodeexporter"}
                ${length(regexall("admin", var.name)) > 0 ? "echo" : "sudo systemctl enable nodeexporter"}
                ${length(regexall("admin", var.name)) > 0 ? "sudo systemctl start consulexporter" : "echo"}
                ${length(regexall("admin", var.name)) > 0 ? "sudo systemctl enable consulexporter" : "echo"}
                sudo systemctl start promtail
                sudo systemctl enable promtail
            EOF
        ]
    }

    connection {
        host = var.public_ip
        type = "ssh"
    }
}

###NOTE: If we were to migrate to ansible for exporters (couldnt be run here without ansible_hostfile created already), 
###  this is the resource we'd roughly use. Wrote it, but not necessary atm

#resource "null_resource" "exporters" {
#    count = var.admin_ip_private == "" ? 0 : local.server_count
#    depends_on = [
#        null_resource.access,
#        null_resource.reprovision_scripts,
#        null_resource.consul_checks,
#    ]
#
#    provisioner "local-exec" {
#        command = <<-EOF
#            ansible-playbook ${path.module}/playbooks/nodeexporter.yml -i ${var.ansible_hostfile} --extra-vars \
#                "nodeexporter_version=${var.nodeexporter_version} \
#                promtail_version=${var.promtail_version} \
#                consulexporter_version=${var.consulexporter_version}"
#        EOF
#    }
#}
