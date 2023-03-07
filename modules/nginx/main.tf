variable "ansible_hosts" {}
variable "ansible_hostfile" {}

variable "lead_servers" {}

variable "root_domain_name" { default = "" }
variable "additional_domains" { default = {} }
variable "additional_ssl" { default = [] }
variable "cert_port" {}
variable "kubernetes_nginx_nodeports" {}

variable "app_definitions" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string, docker_registry=string, docker_registry_image=string,
        docker_registry_url=string, docker_registry_user=string, docker_registry_pw=string, service_name=string,
        green_service=string, blue_service=string, default_active=string,
        create_dns_record=string, create_dev_dns=string, create_ssl_cert=string, subdomain_name=string
    }))
}

locals {
    lead_private_ips = flatten([
        for role, hosts in var.ansible_hosts: [
            for HOST in hosts: HOST.private_ip
            if contains(HOST.roles, "lead")
        ]
    ])
    docker_subdomains = [
        for app in var.app_definitions:
        format("%s.%s", app.subdomain_name, var.root_domain_name)
        if app.create_dns_record == "true" && app.create_ssl_cert == "true"
    ]
    docker_services = [
        for app in var.app_definitions:
        { subdomain = format("%s.%s", app.subdomain_name, var.root_domain_name), port = regex(":[0-9]+", app.green_service) }
        if app.create_dns_record == "true" && app.create_ssl_cert == "true"
    ]
    kubernetes_subdomains = [
        for app in var.additional_ssl:
        format("%s.%s", app.subdomain_name, var.root_domain_name)
        if app.create_ssl_cert == true
    ]
}


##TODO: Implement handlers/notifys in ansible to reload nginx/gitlab
resource "null_resource" "provision" {
    triggers = {
        num_apps = length(keys(var.app_definitions))
        num_ssl = length(var.additional_ssl)
        lead_servers = var.lead_servers
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
                docker_subdomains=${jsonencode(local.docker_subdomains)}
                docker_services=${jsonencode(local.docker_services)}
                kubernetes_nginx_ip="${element(local.lead_private_ips, 0)}"
                kubernetes_nginx_port="31000"
                kubernetes_nginx_nodeports="${jsonencode(var.kubernetes_nginx_nodeports)}"
                kubernetes_subdomains=${jsonencode(local.kubernetes_subdomains)}
                additional_domains=${jsonencode(var.additional_domains)}
                proxy_ip="172.17.0.1"'
        EOF
    }
}
