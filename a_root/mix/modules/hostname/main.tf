
variable "server_name_prefix" { default = "" }
variable "region" { default = "" }
variable "hostname" { default = "" }
variable "names" { default = "" }
variable "servers" { default = 0 }
variable "public_ips" { default = "" }
variable "private_ips" { default = "" }
variable "alt_hostname" { default = "" }

resource "null_resource" "change_hostname" {
    count      = var.servers

    provisioner "file" {
        content = <<-EOF

            PUB_IP=${element(var.public_ips, count.index)}
            PRIV_IP=${element(var.private_ips, count.index)}

            sudo hostnamectl set-hostname ${var.hostname}
            sed -i "s/.*${var.server_name_prefix}-${var.region}.*/127.0.1.1 ${var.hostname} ${element(var.names, count.index)}/" /etc/hosts
            sed -i "$ a 127.0.1.1 ${var.hostname} ${element(var.names, count.index)}" /etc/hosts
            sed -i "$ a $PUB_IP ${var.hostname} ${var.alt_hostname}" /etc/hosts

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
        ]
    }

    connection {
        host = element(var.public_ips, count.index)
        type = "ssh"
    }
}
