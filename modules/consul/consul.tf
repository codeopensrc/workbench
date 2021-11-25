variable "ansible_hosts" {}
variable "ansible_hostfile" {}
variable "predestroy_hostfile" {}
variable "region" {}
variable "server_count" {}
variable "force_consul_rebootstrap" { default = false }

locals {
    all_names = [for h in var.ansible_hosts: h.name]
    all_public_ips = [ for h in var.ansible_hosts: h.ip ]
}

resource "null_resource" "start" {
    triggers = {
        server_count = var.server_count
    }
    ## Run playbook with old ansible file and new names to find out the ones to be deleted, drain and removing them
    provisioner "local-exec" {
        command = <<-EOF
            if [ -f "${var.predestroy_hostfile}" ]; then
                ansible-playbook ${path.module}/playbooks/consul_rm.yml -i ${var.predestroy_hostfile} \
                    --extra-vars 'all_names=${jsonencode(local.all_names)} all_public_ips=${jsonencode(local.all_public_ips)}'
            fi
        EOF
    }
    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ${path.module}/playbooks/consul.yml -i ${var.ansible_hostfile} \
                --extra-vars \
               'force_rebootstrap=${var.force_consul_rebootstrap}
               region=${var.region}'
        EOF
    }
}
