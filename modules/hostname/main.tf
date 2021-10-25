
variable "server_name_prefix" { default = "" }
variable "region" { default = "" }
variable "hostname" { default = "" }
variable "name" { default = "" }
variable "public_ip" { default = "" }
variable "private_ip" { default = "" }
variable "root_domain_name" { default = "" }


resource "null_resource" "change_hostname" {

    provisioner "file" {
        # We want hostname to be the name of the machine for all except postfix/gitlab machine
        # Until we learn more about mail server settings, we want the hostname of it to be gitlab.DOMAIN.COM
        content = <<-EOF

            PUB_IP=${var.public_ip}
            PRIV_IP=${var.private_ip}
            OUR_NAME=${ length(regexall("admin", var.name)) > 0 ? var.hostname : var.name }
            OUR_HOSTNAME=${ length(regexall("admin", var.name)) > 0 ? var.hostname : var.root_domain_name }

            sudo hostnamectl set-hostname $OUR_NAME
            sed -i "s/.*${var.server_name_prefix}-${var.region}.*/127.0.1.1 $OUR_HOSTNAME ${var.name}/" /etc/hosts
            sed -i "$ a $PUB_IP ${var.root_domain_name} $OUR_NAME" /etc/hosts

            if [ "$PRIV_IP" != "$PUB_IP" ]; then
                sed -i "$ a $PRIV_IP vpc.my_private_ip" /etc/hosts
            fi
        EOF
        destination = "/tmp/change_hostname.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "cat /etc/hosts",
            "chmod +x /tmp/change_hostname.sh",
            "/tmp/change_hostname.sh",
            "cat /etc/hosts",
        ]
    }

    connection {
        host = var.public_ip
        type = "ssh"
    }
}
