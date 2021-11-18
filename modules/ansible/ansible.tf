variable "ansible_hostfile" { default = "" }
variable "ansible_hosts" { default = "" }

locals {
    admin_public_ips = [
        for HOST in var.ansible_hosts:
        HOST.ip
        if contains(HOST.roles, "admin")
    ]
    lead_public_ips = [
        for HOST in var.ansible_hosts:
        HOST.ip
        if contains(HOST.roles, "lead")
    ]
    db_public_ips = [
        for HOST in var.ansible_hosts:
        HOST.ip
        if contains(HOST.roles, "db")
    ]
    build_public_ips = [
        for HOST in var.ansible_hosts:
        HOST.ip
        if contains(HOST.roles, "build")
    ]
}
## Setting variables in ansible
#https://docs.ansible.com/ansible/latest/user_guide/playbooks_variables.html#setting-variables

resource "null_resource" "ansible_hosts" {
    triggers = {
        ansible_ips = join(",", var.ansible_hosts[*].ip)
        hostfile = var.ansible_hostfile
    }

    provisioner "local-exec" {
        command = <<-EOF
		cat <<-EOLF > ${var.ansible_hostfile}
		[servers]
		%{ for ind, HOST in var.ansible_hosts ~}
		${HOST.ip} machine_name=${HOST.name}
		%{ endfor ~}
		
		%{ if length(local.admin_public_ips) > 0 ~}
		[admin]
		%{ for ind, HOST in var.ansible_hosts ~}
		%{ if contains(HOST.roles, "admin") ~}
		${HOST.ip} machine_name=${HOST.name}
		%{ endif ~}
		%{ endfor ~}
		%{ endif ~}
		
		%{ if length(local.lead_public_ips) > 0 ~}
		[lead]
		%{ for ind, HOST in var.ansible_hosts ~}
		%{ if contains(HOST.roles, "lead") ~}
		${HOST.ip} machine_name=${HOST.name}
		%{ endif ~}
		%{ endfor ~}
		%{ endif ~}
		
		%{ if length(local.db_public_ips) > 0 ~}
		[db]
		%{ for ind, HOST in var.ansible_hosts ~}
		%{ if contains(HOST.roles, "db") ~}
		${HOST.ip} machine_name=${HOST.name}
		%{ endif ~}
		%{ endfor ~}
		%{ endif ~}
		
		%{ if length(local.build_public_ips) > 0 ~}
		[build]
		%{ for ind, HOST in var.ansible_hosts ~}
		%{ if contains(HOST.roles, "build") ~}
		${HOST.ip} machine_name=${HOST.name}
		%{ endif ~}
		%{ endfor ~}
		%{ endif ~}
		
		[all:vars]
		ansible_python_interpreter=/usr/bin/python3
		EOLF
        EOF
    }
    provisioner "local-exec" {
        when = destroy
        command = "rm ./${self.triggers.hostfile}"
        on_failure = continue
    }
}
