variable "ansible_hosts" {}
variable "ansible_hostfile" {}
variable "predestroy_hostfile" {}

variable "gitlab_runner_tokens" {}

variable "lead_servers" {}
variable "build_servers" {}

variable "runners_per_machine" {}
variable "root_domain_name" {}

locals {
    public_ips = flatten([
        for role, hosts in var.ansible_hosts: [
            for HOST in hosts: HOST.ip
            if contains(HOST.roles, "lead") || contains(HOST.roles, "build")
        ]
    ])
}

### Older comments - revisit in future
##### NOTE: After obtaining the token we register the runner from the page
# TODO: Figure out a way to retrieve the token programmatically

# For a fresh project
# https://docs.gitlab.com/ee/api/projects.html#create-project
# For now this is overkill but we need to create the project, get its id, retrieve a private token
#   with api scope, make a curl request to get the project level runners_token and use that
# Programatically creating the project is a little tedious but honestly not a bad idea
#  considering we can then just push the code and images up if we didnt/dont have a backup

## TODO: Now that we're building (needs thorough testing first) using buildctl/buildkit inside
##  kubernetes with the kubernetes executor, we dont (shouldnt) be creating shell runners meaning
##  we dont really need this step anymore
## If anything since we cant register runners until we have a working cluster, we can refactor this
##  a bit and provision kubernetes runners after cluster is up
resource "null_resource" "provision" {
    triggers = {
        num_machines = sum([var.lead_servers + var.build_servers])
        num_runners = sum([var.lead_servers + var.build_servers]) * var.runners_per_machine
    }
    provisioner "local-exec" {
        command = <<-EOF
            if [ -f "${var.predestroy_hostfile}" ]; then
                ansible-playbook ${path.module}/playbooks/cirunners_rm.yml -i ${var.predestroy_hostfile} \
                    --extra-vars 'public_ips=${jsonencode(local.public_ips)}';
            fi
        EOF
    }
    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ${path.module}/playbooks/cirunners.yml -i ${var.ansible_hostfile} --extra-vars \
                'root_domain_name="${var.root_domain_name}"
                runners_per_machine=${var.runners_per_machine}
                gitlab_runner_tokens=${jsonencode(var.gitlab_runner_tokens)}'
        EOF
    }
}
