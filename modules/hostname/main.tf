
variable "server_name_prefix" { default = "" }
variable "region" { default = "" }
variable "hostname" { default = "" }
variable "names" { default = "" }
variable "servers" { default = 0 }
variable "public_ips" { default = "" }
variable "private_ips" { default = "" }
variable "root_domain_name" { default = "" }

variable "prev_module_output" {}

resource "null_resource" "change_hostname" {
    count      = var.servers

    provisioner "file" {
        # We want hostname to be the name of the machine for all except postfix/gitlab machine
        # Until we learn more about mail server settings, we want the hostname of it to be gitlab.DOMAIN.COM
        content = <<-EOF
            echo ${join(",", var.prev_module_output)}

            PUB_IP=${element(var.public_ips, count.index)}
            PRIV_IP=${element(var.private_ips, count.index)}
            OUR_NAME=${ length(regexall("admin", element(var.names, count.index))) > 0 ? var.hostname : element(var.names, count.index) }

            sudo hostnamectl set-hostname $OUR_NAME
            sed -i "s/.*${var.server_name_prefix}-${var.region}.*/127.0.1.1 ${var.hostname} ${element(var.names, count.index)}/" /etc/hosts
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
        host = element(var.public_ips, count.index)
        type = "ssh"
    }
}
