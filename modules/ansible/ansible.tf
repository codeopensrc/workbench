variable "ansible_hostfile" { default = "" }
variable "predestroy_hostfile" { default = "" }
variable "ansible_hosts" { default = "" }

## Setting variables in ansible
#https://docs.ansible.com/ansible/latest/user_guide/playbooks_variables.html#setting-variables

## As a general note while repurposing to ansible - be sure review all bools in template scripts
## Otherwise this can happen during variable templating/substitution/using jsonencode
## CREATE_SSL=True;
## if [ "$CREATE_SSL" = "true" ]; then

## NOTE: Not sure if we want/need to sort for trigger/servers group
resource "null_resource" "ansible_hosts" {
    triggers = {
        num_hosts = length(var.ansible_hosts[*].ip)
        hostfile = var.ansible_hostfile
    }

    provisioner "local-exec" {
        command = <<-EOF
		cat <<-EOLF > ${var.ansible_hostfile}
		[servers]
		%{ for ind, HOST in var.ansible_hosts ~}
		${HOST.ip} machine_name=${HOST.name} private_ip=${HOST.private_ip}
		%{ endfor ~}
		
		[admin]
		%{ for ind, HOST in var.ansible_hosts ~}
		%{ if contains(HOST.roles, "admin") ~}
		${HOST.ip} machine_name=${HOST.name} private_ip=${HOST.private_ip}
		%{ endif ~}
		%{ endfor ~}
		
		[lead]
		%{ for ind, HOST in var.ansible_hosts ~}
		%{ if contains(HOST.roles, "lead") ~}
		${HOST.ip} machine_name=${HOST.name} private_ip=${HOST.private_ip}
		%{ endif ~}
		%{ endfor ~}
		
		[db]
		%{ for ind, HOST in var.ansible_hosts ~}
		%{ if contains(HOST.roles, "db") ~}
		${HOST.ip} machine_name=${HOST.name} private_ip=${HOST.private_ip}
		%{ endif ~}
		%{ endfor ~}
		
		[build]
		%{ for ind, HOST in var.ansible_hosts ~}
		%{ if contains(HOST.roles, "build") ~}
		${HOST.ip} machine_name=${HOST.name} private_ip=${HOST.private_ip}
		%{ endif ~}
		%{ endfor ~}
		
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

## Should only trigger on `terraform destroy` to cleanup
resource "null_resource" "rm_predestroy_file" {
    triggers = {
        predestroy_hostfile = var.predestroy_hostfile
    }
    provisioner "local-exec" {
        when = destroy
        command = "rm ./${self.triggers.predestroy_hostfile}"
        on_failure = continue
    }
}
