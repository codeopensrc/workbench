variable "ansible_hostfile" { default = "" }
variable "predestroy_hostfile" { default = "" }
variable "ansible_hosts" { default = "" }

##TODO: Test sorting by descending creation_time so scaling up adds machines
##  but scaling down removes the oldest node - builds or leads servers that are not kube admins
## Dont think its fully achievable until almost ALL provisioning done via ansible due to terraform
##   needing the exact resource count and any random names/uuids known before apply, otherwise we're
##   just doing more complicated indexed based provisioning

locals {
    time_grouped_hosts = {
        for ind, host in var.ansible_hosts: (host.creation_time) => host...
    }
    time_then_size_grouped_hosts = {
        for time, hosts in local.time_grouped_hosts:
        (time) => { for host in hosts: (host.size_priority) => host... }
    }
    sorted_times = sort(distinct(var.ansible_hosts[*].creation_time))
    sorted_sizes = reverse(sort(distinct(var.ansible_hosts[*].size_priority)))
    sorted_hosts = flatten([
        for time in local.sorted_times: [
            for size in local.sorted_sizes:
            local.time_then_size_grouped_hosts[time][size]
            if lookup(local.time_then_size_grouped_hosts[time], size, "") != ""
        ]
    ])
}

output "hosts" {
    value = local.sorted_hosts
}

## Setting variables in ansible
#https://docs.ansible.com/ansible/latest/user_guide/playbooks_variables.html#setting-variables

## NOTE: Not sure if we want/need to sort for trigger/servers group
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
		
		[admin]
		%{ for ind, HOST in local.sorted_hosts ~}
		%{ if contains(HOST.roles, "admin") ~}
		${HOST.ip} machine_name=${HOST.name}
		%{ endif ~}
		%{ endfor ~}
		
		[lead]
		%{ for ind, HOST in local.sorted_hosts ~}
		%{ if contains(HOST.roles, "lead") ~}
		${HOST.ip} machine_name=${HOST.name}
		%{ endif ~}
		%{ endfor ~}
		
		[db]
		%{ for ind, HOST in local.sorted_hosts ~}
		%{ if contains(HOST.roles, "db") ~}
		${HOST.ip} machine_name=${HOST.name}
		%{ endif ~}
		%{ endfor ~}
		
		[build]
		%{ for ind, HOST in local.sorted_hosts ~}
		%{ if contains(HOST.roles, "build") ~}
		${HOST.ip} machine_name=${HOST.name}
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
