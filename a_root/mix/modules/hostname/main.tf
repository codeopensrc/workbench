
variable "server_name_prefix" { default = "" }
variable "region" { default = "" }
variable "hostname" { default = "" }
variable "names" { default = "" }
variable "servers" { default = 0 }
variable "public_ips" { default = "" }
variable "alt_hostname" { default = "" }

resource "null_resource" "change_hostname" {
    count      = var.servers

    provisioner "remote-exec" {
        inline = [
            "sudo hostnamectl set-hostname ${var.hostname}",
            "sed -i 's/.*${var.server_name_prefix}-${var.region}.*/127.0.1.1 ${var.hostname} ${element(var.names, count.index)}/' /etc/hosts",
            "sed -i '$ a 127.0.1.1 ${var.hostname} ${element(var.names, count.index)}' /etc/hosts",
            "sed -i '$ a ${element(var.public_ips, count.index)} ${var.hostname} ${var.alt_hostname}' /etc/hosts",
            "cat /etc/hosts"
        ]
        connection {
            host = element(var.public_ips, count.index)
            type = "ssh"
        }
    }
}


output "resource_ids" { value = null_resource.change_hostname[*].id }
