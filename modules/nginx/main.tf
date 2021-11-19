variable "ansible_hosts" {}
variable "ansible_hostfile" {}

variable "admin_servers" {}
variable "is_only_lead_servers" {}
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
    lead_public_ips = [
        for HOST in var.ansible_hosts:
        HOST.ip
        if contains(HOST.roles, "lead")
    ]
    lead_private_ips = [
        for HOST in var.ansible_hosts:
        HOST.private_ip
        if contains(HOST.roles, "lead")
    ]
}


## TODO: ansible playbook
resource "null_resource" "proxy_config" {
    count = var.admin_servers + var.is_only_lead_servers

    triggers = {
        num_apps = length(keys(var.app_definitions))
        num_ssl = length(var.additional_ssl)
        num_ips = length(local.lead_private_ips)
    }

    provisioner "remote-exec" {
        inline = [ "mkdir -p /etc/nginx/conf.d" ]
    }

    provisioner "file" {
        content = templatefile("${path.module}/templatefiles/mainproxy.tmpl", {
            root_domain_name = var.root_domain_name
            proxy_ip = "172.17.0.1" #docker0 subnet
            cert_port = var.cert_port
            cert_domain = "cert.${var.root_domain_name}"
            subdomains = [
                for HOST in var.app_definitions:
                format("%s.%s", HOST.subdomain_name, var.root_domain_name)
                if HOST.create_dns_record == "true" && HOST.create_ssl_cert == "true"
            ]
            services = [
                for HOST in var.app_definitions:
                { subdomain = format("%s.%s", HOST.subdomain_name, var.root_domain_name), port = regex(":[0-9]+", HOST.green_service) }
                if HOST.create_dns_record == "true" && HOST.create_ssl_cert == "true"
            ]
        })
        destination = "/etc/nginx/conf.d/proxy.conf"
    }

    provisioner "file" {
        content = templatefile("${path.module}/templatefiles/kube_services.tmpl", {
            root_domain_name = var.root_domain_name
            cert_port = var.cert_port
            cert_domain = "cert.${var.root_domain_name}"
            kube_nginx_ip = element(local.lead_private_ips, 0)
            kube_nginx_port = "31000"  #Hardcoded nginx NodePort service atm
            subdomains = [
                for HOST in var.additional_ssl:
                format("%s.%s", HOST.subdomain_name, var.root_domain_name)
                if HOST.create_ssl_cert == true
            ]
        })
        destination = "/etc/nginx/conf.d/kube_services.conf"
    }

    connection {
        ## admin_ips and lead_ips NOT in admin_ips
        ##TODO: tolist(setsubtract()) will always create an unpredictable ip order no matter previous sort until ansible
        host = element(concat(local.admin_public_ips, tolist(setsubtract(local.lead_public_ips, local.admin_public_ips))), count.index)
        type = "ssh"
    }
}

resource "null_resource" "proxy_additional_config" {
    count = var.admin_servers > 0 ? length(keys(var.additional_domains)) : 0
    depends_on = [ null_resource.proxy_config ]

    triggers = {
        subdomains = join(",", keys(element(values(var.additional_domains), count.index)))
        num_domains = length(keys(var.additional_domains))
        ip = element(local.admin_public_ips, 0)
    }

    provisioner "file" {
        content = templatefile("${path.module}/templatefiles/additional.tmpl", {
            root_domain_name = element(keys(var.additional_domains), count.index)
            subdomains = element(values(var.additional_domains), count.index)
            cert_port = var.cert_port
        })
        destination = "/etc/nginx/conf.d/additional-${count.index}.conf"
        connection {
            host = element(local.admin_public_ips, 0)
            type = "ssh"
        }
    }

    provisioner "remote-exec" {
        when = destroy
        inline = [ "rm /etc/nginx/conf.d/additional-${count.index}.conf" ]
        connection {
            host = self.triggers.ip
            type = "ssh"
        }
    }
}


## TODO: ansible playbook
resource "null_resource" "tmp_install_nginx" {
    count = var.is_only_lead_servers
    depends_on = [
        null_resource.proxy_config,
        null_resource.proxy_additional_config,
    ]
    provisioner "remote-exec" {
        inline = [
            <<-EOF
                sudo apt install curl gnupg2 ca-certificates lsb-release ubuntu-keyring -y
                sudo apt update
                sudo apt install nginx -y
            EOF
        ]
    }
    connection {
        ##TODO: tolist(setsubtract()) will always create an unpredictable ip order no matter previous sort until ansible
        host = element(tolist(setsubtract(local.lead_public_ips, local.admin_public_ips)), count.index)
        type = "ssh"
    }
}

resource "null_resource" "nginx_reconfigure" {
    count = var.admin_servers
    depends_on = [
        null_resource.proxy_config,
        null_resource.proxy_additional_config,
        null_resource.tmp_install_nginx,
    ]

    triggers = {
        mainproxy = join(",", null_resource.proxy_config.*.id)
        additionalproxy  = join(",", null_resource.proxy_additional_config.*.id)
    }

    provisioner "remote-exec" {
        ## TODO: Because of this convenience for config on app change, it has to be run after gitlab is installed

        # Check for ssl certs and uncomment if we have them
        inline = [
            "[ -d \"/etc/letsencrypt/live/${var.root_domain_name}\" ] && sed -i \"s|#ssl_certificate|ssl_certificate|\" /etc/nginx/conf.d/*.conf",
            "[ -d \"/etc/letsencrypt/live/${var.root_domain_name}\" ] && sed -i \"s|#ssl_certificate_key|ssl_certificate_key|\" /etc/nginx/conf.d/*.conf",
            "[ -d \"/etc/letsencrypt/live/${var.root_domain_name}\" ] && sed -i \"s|#listen 443 ssl|listen 443 ssl|\" /etc/nginx/conf.d/*.conf",
            "gitlab-ctl reconfigure"
        ]
    }

    connection {
        host = element(local.admin_public_ips, 0)
        type = "ssh"
    }
}

resource "null_resource" "nginx_reload" {
    count = var.is_only_lead_servers
    depends_on = [
        null_resource.proxy_config,
        null_resource.proxy_additional_config,
        null_resource.tmp_install_nginx,
    ]

    triggers = {
        mainproxy = join(",", null_resource.proxy_config.*.id)
        additionalproxy  = join(",", null_resource.proxy_additional_config.*.id)
    }

    provisioner "remote-exec" {
        ## TODO: Because of this convenience for config on app change, it has to be run after gitlab is installed

        # Check for ssl certs and uncomment if we have them
        inline = [
            "[ -d \"/etc/letsencrypt/live/${var.root_domain_name}\" ] && sed -i \"s|#ssl_certificate|ssl_certificate|\" /etc/nginx/conf.d/*.conf",
            "[ -d \"/etc/letsencrypt/live/${var.root_domain_name}\" ] && sed -i \"s|#ssl_certificate_key|ssl_certificate_key|\" /etc/nginx/conf.d/*.conf",
            "[ -d \"/etc/letsencrypt/live/${var.root_domain_name}\" ] && sed -i \"s|#listen 443 ssl|listen 443 ssl|\" /etc/nginx/conf.d/*.conf",
            "sudo systemctl reload nginx",
        ]
    }

    connection {
        ##TODO: tolist(setsubtract()) will always create an unpredictable ip order no matter previous sort until ansible
        host = element(tolist(setsubtract(local.lead_public_ips, local.admin_public_ips)), count.index)
        type = "ssh"
    }
}
