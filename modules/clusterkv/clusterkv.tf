variable "app_definitions" { default = [] }
variable "additional_ssl" { default = [] }
variable "root_domain_name" { default = "" }
variable "serverkey" { default = "" }
variable "pg_password" { default = "" }
variable "dev_pg_password" { default = "" }

variable "ansible_hostfile" { default = "" }

###### NOTE: Old comment/note below, probably not even applicable anymore with kubernetes and canary deployments etc.
###### Can do canary, blue-green, or simply implement rollbacks if X% issues start happening

#### TODO: Find a way to gradually migrate from blue -> green and vice versa vs
####   just sending all req suddenly from blue to green
#### This way if the deployment was scuffed, it only affects X% of users whether
####   pre-determined  20/80 split etc. or part of slow rollout
#### TODO: We already register a check/service with consul.. maybe have the app also
####   register its consul endpoints as well?


## NOTE: Only thing for this is consul needs to be installed
## Not really sure if we just fail if no consul/cluster leader or try checking and print detailed info if fail
resource "null_resource" "add_consul_kv" {
    triggers = {
        num_apps = length(keys(var.app_definitions))
        additional_ssl = join(",", [
            for app in var.additional_ssl:
            app.service_name
            if app.create_ssl_cert == true
        ])
    }

    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ${path.module}/playbooks/clusterkv.yml -i ${var.ansible_hostfile} --extra-vars \
                'app_definitions=${jsonencode(var.app_definitions)} additional_ssl=${jsonencode(var.additional_ssl)} \
                root_domain_name=${var.root_domain_name} serverkey=${var.serverkey} pg_password=${var.pg_password} dev_pg_password=${var.dev_pg_password}'
        EOF
    }
}
