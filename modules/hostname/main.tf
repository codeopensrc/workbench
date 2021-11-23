variable "ansible_hostfile" {}
variable "server_count" {}

variable "region" { default = "" }
variable "server_name_prefix" { default = "" }
variable "root_domain_name" { default = "" }
variable "hostname" { default = "" }

resource "null_resource" "change_hostname" {
    triggers = {
        server_count = var.server_count
    }
    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ${path.module}/playbooks/hostname.yml -i ${var.ansible_hostfile} \
                --extra-vars \
                'server_name_prefix=${var.server_name_prefix}
                region=${var.region}
                hostname=${var.hostname}
                root_domain_name=${var.root_domain_name}'
        EOF
    }
}
