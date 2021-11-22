variable "ansible_hostfile" {}
variable "server_count" {}

variable "known_hosts" { default = [] }
variable "root_domain_name" {}
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

## Place public ssh keys of git repository hosting service in known_hosts, normally available through the provider
##   See the bitbucket example already in templatefiles/known_hosts
## If intending to host a gitlab instance. The entry that goes into known_hosts is the PUBLIC key of the ssh SERVER found at /etc/ssh/ssh_host_rsa_key.pub
##   for your server that hosts the sub domain gitlab.ROOTDOMAIN.COM.
## TODO: Determine best way to use identity files and remote repo locations
resource "null_resource" "files" {
    triggers = {
        server_count = var.server_count
    }
    provisioner "local-exec" {
        command = <<-EOF
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
        EOF
    }
}

