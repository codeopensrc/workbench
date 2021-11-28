variable "ansible_hostfile" { default = "" }
variable "predestroy_hostfile" { default = "" }
variable "ansible_hosts" { default = "" }
variable "server_count" { default = "" }

## Setting variables in ansible
#https://docs.ansible.com/ansible/latest/user_guide/playbooks_variables.html#setting-variables

## As a general note while repurposing to ansible - be sure review all bools in template scripts
## Otherwise this can happen during variable templating/substitution/using jsonencode
## CREATE_SSL=True;
## if [ "$CREATE_SSL" = "true" ]; then

## From ansible.cfg regarding caching facts:     NOTE: default is memory
# If set to a persistent type (not 'memory', for example 'redis') fact values
# from previous runs in Ansible will be stored.

## Review adding custom facts in facts.d dir
# https://docs.ansible.com/ansible/latest/user_guide/playbooks_vars_facts.html#adding-custom-facts

locals { hosts = flatten(values(var.ansible_hosts)) }

## NOTE: Not sure if we want/need to sort for trigger/servers group
resource "null_resource" "ansible_hosts" {
    triggers = {
        num_hosts = var.server_count
        hostfile = var.ansible_hostfile
    }

    provisioner "local-exec" {
        command = <<-EOF
		cat <<-EOLF > ${var.ansible_hostfile}
		[servers]
		%{ for ind, HOST in local.hosts ~}
		${HOST.ip} machine_name=${HOST.name} private_ip=${HOST.private_ip}
		%{ endfor ~}
		
		[admin]
		%{ for ind, HOST in local.hosts ~}
		%{ if contains(HOST.roles, "admin") ~}
		${HOST.ip} machine_name=${HOST.name} private_ip=${HOST.private_ip}
		%{ endif ~}
		%{ endfor ~}
		
		[lead]
		%{ for ind, HOST in local.hosts ~}
		%{ if contains(HOST.roles, "lead") ~}
		${HOST.ip} machine_name=${HOST.name} private_ip=${HOST.private_ip}
		%{ endif ~}
		%{ endfor ~}
		
		[db]
		%{ for ind, HOST in local.hosts ~}
		%{ if contains(HOST.roles, "db") ~}
		${HOST.ip} machine_name=${HOST.name} private_ip=${HOST.private_ip}
		%{ endif ~}
		%{ endfor ~}
		
		[build]
		%{ for ind, HOST in local.hosts ~}
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
