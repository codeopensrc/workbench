variable "ansible_hosts" {}
variable "ansible_hostfile" {}
variable "predestroy_hostfile" {}

variable "region" {}
variable "server_count" {}
variable "force_consul_rebootstrap" { default = false }

variable "app_definitions" { default = [] }
variable "additional_ssl" { default = [] }
variable "root_domain_name" { default = "" }
variable "pg_password" { default = "" }
variable "dev_pg_password" { default = "" }

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


###### NOTE: Old comment/note below, probably not even applicable anymore with kubernetes and canary deployments etc.
###### Can do canary, blue-green, or simply implement rollbacks if X% issues start happening

#### TODO: Find a way to gradually migrate from blue -> green and vice versa vs
####   just sending all req suddenly from blue to green
#### This way if the deployment was scuffed, it only affects X% of users whether
####   pre-determined  20/80 split etc. or part of slow rollout
#### TODO: We already register a check/service with consul.. maybe have the app also
####   register its consul endpoints as well?
resource "null_resource" "kv" {
    depends_on = [ null_resource.start ]
    triggers = {
        num_apps = length(keys(var.app_definitions))
        additional_ssl = join(",", [
            for app in var.additional_ssl:
            app.service_name
            if app.create_ssl_cert == true
        ])
        force_consul_rebootstrap = var.force_consul_rebootstrap
    }

    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ${path.module}/playbooks/kv.yml -i ${var.ansible_hostfile} --extra-vars \
                'app_definitions=${jsonencode(var.app_definitions)} additional_ssl=${jsonencode(var.additional_ssl)} \
                root_domain_name=${var.root_domain_name} pg_password=${var.pg_password} dev_pg_password=${var.dev_pg_password}'
        EOF
    }
}
