variable "ansible_hosts" {}
variable "remote_state_hosts" {}
variable "ansible_hostfile" {}

variable "server_count" {}

variable "region" { default = "" }
variable "server_name_prefix" { default = "" }
variable "root_domain_name" { default = "" }
variable "hostname" { default = "" }

variable "aws_bot_access_key" { default = "" }
variable "aws_bot_secret_key" { default = "" }

variable "do_spaces_region" { default = "" }
variable "do_spaces_access_key" { default = "" }
variable "do_spaces_secret_key" { default = "" }

variable "known_hosts" { default = [] }
variable "deploy_key_location" {}

variable "nodeexporter_version" { default = "" }
variable "promtail_version" { default = "" }
variable "consulexporter_version" { default = "" }
variable "loki_version" { default = "" }

variable "pg_read_only_pw" { default = "" }
variable "postgres_version" { default = "" }
variable "postgres_port" { default = "" }
variable "mongo_version" { default = "" }
variable "mongo_port" { default = "" }
variable "redis_version" { default = "" }
variable "redis_port" { default = "" }

locals {
    all_names = flatten([for role, hosts in var.ansible_hosts: hosts[*].name])
    old_all_names = flatten([for role, hosts in var.remote_state_hosts: hosts[*].name])
}

resource "null_resource" "playbook" {
    triggers = {
        server_count = var.server_count
    }
    provisioner "local-exec" {
        command = <<-EOF
            if [ ${length(local.all_names)} -ge ${length(local.old_all_names)} ]; then
                ansible-playbook ${path.module}/playbooks/init.yml -i ${var.ansible_hostfile} \
                    --extra-vars \
                    'aws_bot_access_key=${var.aws_bot_access_key}
                    aws_bot_secret_key=${var.aws_bot_secret_key}
                    do_spaces_region=${var.do_spaces_region}
                    do_spaces_access_key=${var.do_spaces_access_key}
                    do_spaces_secret_key=${var.do_spaces_secret_key}
                    server_name_prefix=${var.server_name_prefix}
                    region=${var.region}
                    hostname=${var.hostname}
                    root_domain_name=${var.root_domain_name}'
            fi
        EOF
    }

    ## Place public ssh keys of git repository hosting service in known_hosts, normally available through the provider
    ##   See the bitbucket example already in templatefiles/known_hosts
    ## If intending to host a gitlab instance. The entry that goes into known_hosts is the PUBLIC key of the ssh SERVER found at /etc/ssh/ssh_host_rsa_key.pub
    ##   for your server that hosts the sub domain gitlab.ROOTDOMAIN.COM.
    ## TODO: Determine best way to use identity files and remote repo locations
    provisioner "local-exec" {
        command = <<-EOF
            if [ ${length(local.all_names)} -ge ${length(local.old_all_names)} ]; then
                ansible-playbook ${path.module}/playbooks/provision.yml -i ${var.ansible_hostfile} \
                    --extra-vars \
                    'nodeexporter_version=${var.nodeexporter_version}
                    promtail_version=${var.promtail_version}
                    loki_version=${var.loki_version}
                    consulexporter_version=${var.consulexporter_version}
                    pg_read_only_pw=${var.pg_read_only_pw}
                    postgres_version=${var.postgres_version}
                    postgres_port=${var.postgres_port}
                    mongo_version=${var.mongo_version}
                    mongo_port=${var.mongo_port}
                    redis_version=${var.redis_version}
                    redis_port=${var.redis_port}
                    deploy_key_location=${var.deploy_key_location}
                    known_hosts_json=${jsonencode(var.known_hosts)}
                    fqdn=${var.root_domain_name}
                    sshconfig_hosts_json=${jsonencode([
                        for HOST in var.known_hosts:
                        HOST.site
                        if HOST.site != "gitlab.${var.root_domain_name}"
                    ])}'
            fi
        EOF
    }

}
