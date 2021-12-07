variable "ansible_hosts" {}
variable "ansible_hostfile" {}
variable "predestroy_hostfile" {}
variable "remote_state_hosts" {}

variable "lead_servers" {}
variable "region" { default = "" }
variable "aws_ecr_region" { default = "" }
variable "container_orchestrators" {}

variable "app_definitions" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string, docker_registry=string, docker_registry_image=string,
        docker_registry_url=string, docker_registry_user=string, docker_registry_pw=string, service_name=string,
        green_service=string, blue_service=string, default_active=string, subdomain_name=string
        use_custom_restore=string, custom_restore_file=string, custom_init=string, custom_vars=string
    }))
}

locals {
    old_lead_public_ips = flatten([
        for role, hosts in var.remote_state_hosts: [
            for HOST in hosts: HOST.ip
            if contains(HOST.roles, "lead")
        ]
    ])
    lead_public_ips = flatten([
        for role, hosts in var.ansible_hosts: [
            for HOST in hosts: HOST.ip
            if contains(HOST.roles, "lead")
        ]
    ])
    lead_names = flatten([
        for role, hosts in var.ansible_hosts: [
            for HOST in hosts: HOST.name
            if contains(HOST.roles, "lead")
        ]
    ])
}

resource "null_resource" "swarm" {
    count = contains(var.container_orchestrators, "docker_swarm") ? 1 : 0
    triggers = {
        num_lead = var.lead_servers
    }
    ## Run playbook with old ansible file and new names to find out the ones to be deleted, drain and removing them
    provisioner "local-exec" {
        command = <<-EOF
            if [ ${length(local.lead_public_ips)} -lt ${length(local.old_lead_public_ips)} ]; then
                if [ -f "${var.predestroy_hostfile}" ]; then
                    ansible-playbook ${path.module}/playbooks/swarm_rm.yml -i ${var.predestroy_hostfile} \
                        --extra-vars 'lead_names=${jsonencode(local.lead_names)} lead_public_ips=${jsonencode(local.lead_public_ips)}';
                fi
            fi
        EOF
    }
    provisioner "local-exec" {
        command = <<-EOF
            if [ ${length(local.lead_public_ips)} -ge ${length(local.old_lead_public_ips)} ]; then
                ansible-playbook ${path.module}/playbooks/swarm.yml -i ${var.ansible_hostfile} --extra-vars "region=${var.region}"
            fi
        EOF
    }
}

resource "null_resource" "services" {
    count = contains(var.container_orchestrators, "docker_swarm") ? 1 : 0
    depends_on = [
        null_resource.swarm,
    ]
    triggers = {
        num_lead = var.lead_servers
        num_apps = length(keys(var.app_definitions))
    }
    provisioner "local-exec" {
        command = <<-EOF
            if [ ${length(local.lead_public_ips)} -ge ${length(local.old_lead_public_ips)} ]; then
                ansible-playbook ${path.module}/playbooks/services.yml -i ${var.ansible_hostfile} --extra-vars \
                    'aws_ecr_region=${var.aws_ecr_region} app_definitions=${jsonencode(var.app_definitions)}'
            fi
        EOF
    }
}

