variable "ansible_hosts" {}
variable "ansible_hostfile" {}

variable "root_domain_name" { default = "" }
variable "additional_domains" { default = {} }
variable "additional_ssl" { default = [] }
variable "cert_port" {}
variable "app_definitions" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string, docker_registry=string, docker_registry_image=string,
        docker_registry_url=string, docker_registry_user=string, docker_registry_pw=string, service_name=string,
        green_service=string, blue_service=string, default_active=string,
        create_dns_record=string, create_dev_dns=string, create_ssl_cert=string, subdomain_name=string
    }))
}

locals {
    admin_public_ips = [
        for HOST in var.ansible_hosts:
        HOST.ip
        if contains(HOST.roles, "admin")
    ]
    lead_private_ips = [
        for HOST in var.ansible_hosts:
        HOST.private_ip
        if contains(HOST.roles, "lead")
    ]
}


##TODO: Implement handlers/notifys in ansible to reload nginx/gitlab
resource "null_resource" "provision" {
    triggers = {
        num_apps = length(keys(var.app_definitions))
        num_ssl = length(var.additional_ssl)
        num_ips = length(local.lead_private_ips)
        ## TODO: List all subdomains from each domain in additional_domains list and join
        #subdomains = join(",", keys(element(values(var.additional_domains), count.index)))
        num_domains = length(keys(var.additional_domains))
    }
    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ${path.module}/playbooks/nginx.yml -i ${var.ansible_hostfile} --extra-vars \
                'root_domain_name="${var.root_domain_name}"
                cert_port=${var.cert_port}
                cert_domain="cert.${var.root_domain_name}"
                docker_subdomains=${jsonencode([
                    for HOST in var.app_definitions:
                    format("%s.%s", HOST.subdomain_name, var.root_domain_name)
                    if HOST.create_dns_record == "true" && HOST.create_ssl_cert == "true"
                ])}
                docker_services=${jsonencode([
                    for HOST in var.app_definitions:
                    { subdomain = format("%s.%s", HOST.subdomain_name, var.root_domain_name), port = regex(":[0-9]+", HOST.green_service) }
                    if HOST.create_dns_record == "true" && HOST.create_ssl_cert == "true"
                ])}
                kubernetes_nginx_ip="${element(local.lead_private_ips, 0)}"
                kubernetes_nginx_port="31000"
                kubernetes_subdomains=${jsonencode([
                    for HOST in var.additional_ssl:
                    format("%s.%s", HOST.subdomain_name, var.root_domain_name)
                    if HOST.create_ssl_cert == true
                ])}
                additional_domains=${jsonencode(var.additional_domains)}
                proxy_ip="172.17.0.1"'
        EOF
    }
}
