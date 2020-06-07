
variable "role" { default = "" }
variable "import_dbs" { default = false }
variable "servers" { default = 0 }
variable "public_ips" { default = "" }

variable "db_backups_enabled" { default = false }
variable "run_service_enabled" { default = false }
variable "send_logs_enabled" { default = false }
variable "send_jsons_enabled" { default = false }

variable "prev_module_output" {}

variable "known_hosts" { default = [] }
variable "active_env_provider" { default = "" }
variable "root_domain_name" { default = "" }
variable "deploy_key_location" {}

variable "pg_read_only_pw" { default = "" }
variable "private_ips" {
    type = list(string)
    default = []
}


resource "null_resource" "base_files" {
    count = var.servers

    triggers = {
        wait_for_prev_module = "${join(",", var.prev_module_output)}"
    }

    provisioner "file" {
        content = <<-EOF
            [credential]
                helper = store
        EOF
        destination = "/root/.gitconfig"
    }

    provisioner "file" {
        source = "${path.module}/files/tmux.conf"
        destination = "/root/.tmux.conf"
    }

    provisioner "remote-exec" {
        inline = [
            "mkdir -p /root/repos",
            "mkdir -p /root/builds",
            "mkdir -p /root/code",
            "mkdir -p /root/code/logs",
            "mkdir -p /root/code/backups",
            "mkdir -p /root/code/scripts",
            "mkdir -p /root/code/csv",
            "mkdir -p /root/code/jsons",
            "mkdir -p /root/.ssh",
            "mkdir -p /root/.tmux/plugins",
            "mkdir -p /etc/ssl/creds",
            "(cd /root/.ssh && ssh-keygen -f id_rsa -t rsa -N '')",
            "cat /usr/share/zoneinfo/America/Los_Angeles > /etc/localtime",
            "timedatectl set-timezone 'America/Los_Angeles'",
            "sudo apt-get update",
            "sudo apt-get install build-essential apt-utils openjdk-8-jdk vim git awscli -y",
            "git clone https://github.com/tmux-plugins/tpm /root/.tmux/plugins/tpm",
        ]
        # TODO: Configurable timezone
    }

    provisioner "file" {
        source = "${path.module}/scripts/"
        destination = "/root/code/scripts"
    }

    provisioner "file" {
        source = "${path.module}/import/"
        destination = "/root/code/scripts"
    }
    provisioner "file" {
        source = "${path.module}/install/"
        destination = "/root/code/scripts"
    }

    provisioner "file" {
        content = fileexists("${path.module}/ignore/authorized_keys") ? file("${path.module}/ignore/authorized_keys") : ""
        destination = "/root/.ssh/authorized_keys"
    }

    provisioner "file" {
        content = file("${path.module}/files/checkssl.sh")
        destination = "/root/code/scripts/checkssl.sh"
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
            "/tmp/cronscripts.sh"
        ]
    }

    connection {
        host = element(var.public_ips, count.index)
        type = "ssh"
    }
}



resource "null_resource" "access" {
    count = var.servers
    depends_on = [
        null_resource.base_files
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

    # NOTE: Populate the known_hosts entry for auxiliary servers AFTER we upload our backed up ssh keys to the admin server
    #  The entry that goes into known hosts is the PUBLIC key of the ssh SERVER found at /etc/ssh/ssh_host_rsa_key.pub
    #  For the sub domain gitlab.ROOTDOMAIN.COM
    provisioner "file" {
        content = templatefile("${path.module}/templatefiles/known_hosts", {
            known_hosts = var.known_hosts
        })
        destination = "/root/.ssh/known_hosts"
    }

    provisioner "file" {
        content = file("${var.deploy_key_location}")
        destination = "/root/.ssh/deploy.key"
    }
    provisioner "remote-exec" {
        inline = ["chmod 0600 /root/.ssh/deploy.key"]
    }

    connection {
        host = element(var.public_ips, count.index)
        type = "ssh"
    }
}



# TODO: This is temporary until we switch over db urls being application specific
resource "null_resource" "consul_checks" {
    count = var.servers

    depends_on = [
        null_resource.base_files,
        null_resource.access,
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
            ip_address = element(var.active_env_provider == "aws" ? var.private_ips : var.public_ips, count.index)
        })
        destination = "/etc/consul.d/templates/pg.json"
    }

    provisioner "file" {
        content = templatefile("${path.module}/templatefiles/checks/consul_mongo.json", {
            ip_address = element(var.active_env_provider == "aws" ? var.private_ips : var.public_ips, count.index)
        })
        destination = "/etc/consul.d/templates/mongo.json"
    }

    provisioner "file" {
        content = file("${path.module}/templatefiles/checks/consul_redis.json")
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
        host = element(var.public_ips, count.index)
        type = "ssh"
    }
}

output "output" {
    depends_on = [
        null_resource.base_files,
        null_resource.access,
        null_resource.consul_checks,
    ]
    value = null_resource.consul_checks.*.id
}
