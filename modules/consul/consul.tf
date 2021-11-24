variable "ansible_hostfile" {}
variable "region" {}
variable "server_count" {}
variable "force_consul_rebootstrap" { default = false }

resource "null_resource" "start" {
    triggers = {
        server_count = var.server_count
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
