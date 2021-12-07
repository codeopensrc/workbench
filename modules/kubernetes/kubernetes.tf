variable "ansible_hosts" {}
variable "ansible_hostfile" {}
variable "predestroy_hostfile" {}
variable "remote_state_hosts" {}

variable "admin_servers" {}
variable "server_count" {}

variable "gitlab_runner_tokens" {}
variable "root_domain_name" {}
variable "import_gitlab" {}
variable "vpc_private_iface" {}

variable "kubernetes_version" {}
variable "container_orchestrators" {}

locals {
    all_names = flatten([for role, hosts in var.ansible_hosts: hosts[*].name])
    old_all_names = flatten([for role, hosts in var.remote_state_hosts: hosts[*].name])
    admin_private_ips = flatten([
        for role, hosts in var.ansible_hosts: [
            for HOST in hosts: HOST.private_ip
            if contains(HOST.roles, "admin")
        ]
    ])
    lead_private_ips = flatten([
        for role, hosts in var.ansible_hosts: [
            for HOST in hosts: HOST.private_ip
            if contains(HOST.roles, "lead")
        ]
    ])
}

resource "null_resource" "kubernetes" {
    count = contains(var.container_orchestrators, "kubernetes") ? 1 : 0
    triggers = {
        num_nodes = var.server_count
    }

    ## Run playbook with old ansible file and new names to find out the ones to be deleted, drain and removing them
    provisioner "local-exec" {
        command = <<-EOF
            if [ ${length(local.all_names)} -lt ${length(local.old_all_names)} ]; then
                if [ -f "${var.predestroy_hostfile}" ]; then
                    ansible-playbook ${path.module}/playbooks/kubernetes_rm.yml -i ${var.predestroy_hostfile} --extra-vars \
                        'all_names=${jsonencode(local.all_names)}
                        admin_private_ips=${jsonencode(local.admin_private_ips)}
                        lead_private_ips=${jsonencode(local.lead_private_ips)}';
                fi
            fi
        EOF
    }
    ##  digitaloceans private iface = eth1
    ##  aws private iface = ens5
    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ${path.module}/playbooks/kubernetes.yml -i ${var.ansible_hostfile} --extra-vars \
                'kubernetes_version=${var.kubernetes_version}
                gitlab_runner_tokens=${jsonencode(var.gitlab_runner_tokens)}
                vpc_private_iface=${var.vpc_private_iface}
                root_domain_name=${var.root_domain_name}
                admin_servers=${var.admin_servers}
                server_count=${var.server_count}
                import_gitlab=${var.import_gitlab}'
        EOF
    }
}

