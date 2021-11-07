
variable "ansible_hostfile" { default = "" }
variable "ansible_hosts" { default = "" }

variable "all_public_ips" { default = "" }
variable "admin_public_ips" { default = "" }
variable "lead_public_ips" { default = "" }
variable "db_public_ips" { default = "" }
variable "build_public_ips" { default = "" }

## Setting variables in ansible
#https://docs.ansible.com/ansible/latest/user_guide/playbooks_variables.html#setting-variables

resource "null_resource" "ansible_hosts" {
    triggers = {
        ips = join(",", var.all_public_ips)
        hostfile = var.ansible_hostfile
    }

    provisioner "local-exec" {
        command = <<-EOF
		cat <<-EOLF > ${var.ansible_hostfile}
		[servers]
		%{ for ind, HOST in var.ansible_hosts ~}
		${HOST.name} ansible_host=${HOST.ip}
		%{ endfor ~}
		
		%{ if length(var.admin_public_ips) > 0 ~}
		[admin]
		%{ for ind, HOST in var.ansible_hosts ~}
		%{ if contains(HOST.roles, "admin") ~}
		${HOST.name}_admin ansible_host=${HOST.ip}
		%{ endif ~}
		%{ endfor ~}
		%{ endif ~}
		
		%{ if length(var.lead_public_ips) > 0 ~}
		[lead]
		%{ for ind, HOST in var.ansible_hosts ~}
		%{ if contains(HOST.roles, "lead") ~}
		${HOST.name}_lead ansible_host=${HOST.ip}
		%{ endif ~}
		%{ endfor ~}
		%{ endif ~}
		
		%{ if length(var.db_public_ips) > 0 ~}
		[db]
		%{ for ind, HOST in var.ansible_hosts ~}
		%{ if contains(HOST.roles, "db") ~}
		${HOST.name}_db ansible_host=${HOST.ip}
		%{ endif ~}
		%{ endfor ~}
		%{ endif ~}
		
		%{ if length(var.build_public_ips) > 0 ~}
		[build]
		%{ for ind, HOST in var.ansible_hosts ~}
		%{ if contains(HOST.roles, "build") ~}
		${HOST.name}_build ansible_host=${HOST.ip}
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
