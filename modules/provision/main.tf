
variable "public_ip" { default = "" }
variable "known_hosts" { default = [] }
variable "root_domain_name" { default = "" }
variable "deploy_key_location" {}

variable "private_ip" { default = "" }
variable "pg_read_only_pw" { default = "" }


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

