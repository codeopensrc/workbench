#  *Nginx proxies require an nginx config change/hup once we get certs
# Boils down to, the server/ip var.root_domain_name points to, needs a proxy for port 80/http initially
# After getting certs, restart then supports https and http -> https
variable "ansible_hosts" {}
variable "ansible_hostfile" {}

variable "lead_servers" {}

variable "app_definitions" {}
variable "additional_ssl" {}

variable "root_domain_name" {}
variable "contact_email" {}

resource "null_resource" "ssl" {
    triggers = {
        num_apps = length(keys(var.app_definitions))
        num_ssl = length(var.additional_ssl)
    }
    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ${path.module}/playbooks/letsencrypt.yml -i ${var.ansible_hostfile} --extra-vars \
                'apps=${jsonencode(var.app_definitions)}
                fqdn="${var.root_domain_name}"
                email="${var.contact_email}"
                dry_run=false
                ssl=${jsonencode(var.additional_ssl)}'
        EOF
    }
}

resource "null_resource" "distribute_certs" {
    depends_on = [ null_resource.ssl ]
    triggers = {
        num_apps = length(keys(var.app_definitions))
        num_ssl = length(var.additional_ssl)
        lead_servers = var.lead_servers
    }
    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ${path.module}/playbooks/distribute_certs.yml -i ${var.ansible_hostfile} --extra-vars \
                'fqdn="${var.root_domain_name}"'
        EOF
    }
}
