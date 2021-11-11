variable "admin_servers" {}
variable "is_only_lead_servers" {}
variable "root_domain_name" { default = "" }
variable "additional_domains" { default = {} }
variable "additional_ssl" { default = [] }
variable "admin_public_ips" { default = [] }
variable "lead_public_ips" { default = [] }
variable "lead_private_ips" { default = [] }
variable "cert_port" {}
variable "app_definitions" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string, docker_registry=string, docker_registry_image=string,
        docker_registry_url=string, docker_registry_user=string, docker_registry_pw=string, service_name=string,
        green_service=string, blue_service=string, default_active=string,
        create_dns_record=string, create_dev_dns=string, create_ssl_cert=string, subdomain_name=string
    }))
}

## TODO: ansible playbook
resource "null_resource" "tmp_install_nginx" {
    count = var.is_only_lead_servers
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
        host = element(tolist(setsubtract(var.lead_public_ips, var.admin_public_ips)), count.index)
        type = "ssh"
    }
}


## TODO: ansible playbook
resource "null_resource" "proxy_config" {
    count = var.admin_servers + var.is_only_lead_servers
    depends_on = [ null_resource.tmp_install_nginx ]

    triggers = {
        num_apps = length(keys(var.app_definitions))
        num_ssl = length(var.additional_ssl)
        num_ips = length(var.lead_private_ips)
    }

    provisioner "remote-exec" {
        # TODO: Test if changing the group necessary or not to reading directory for nginx
        #"chown root:gitlab-www /etc/nginx/conf.d"
        inline = [ "mkdir -p /etc/nginx/conf.d" ]
    }

    provisioner "file" {
        content = templatefile("${path.module}/templatefiles/mainproxy.tmpl", {
            root_domain_name = var.root_domain_name
            proxy_ip = element(var.lead_private_ips, length(var.lead_private_ips) - 1 )
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
            kube_nginx_ip = element(var.lead_private_ips, length(var.lead_private_ips) - 1 )
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
        host = element(concat(var.admin_public_ips, var.lead_public_ips), count.index)
        type = "ssh"
    }
}

resource "null_resource" "proxy_additional_config" {
    count = var.admin_servers > 0 ? length(keys(var.additional_domains)) : 0
    depends_on = [ null_resource.tmp_install_nginx ]

    triggers = {
        subdomains = join(",", keys(element(values(var.additional_domains), count.index)))
        num_domains = length(keys(var.additional_domains))
        ip = element(var.admin_public_ips, 0)
    }

    provisioner "file" {
        content = templatefile("${path.module}/templatefiles/additional.tmpl", {
            root_domain_name = element(keys(var.additional_domains), count.index)
            subdomains = element(values(var.additional_domains), count.index)
            cert_port = var.cert_port
        })
        destination = "/etc/nginx/conf.d/additional-${count.index}.conf"
        connection {
            host = element(var.admin_public_ips, 0)
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


resource "null_resource" "nginx_reconfigure" {
    count = var.admin_servers
    depends_on = [
        null_resource.tmp_install_nginx,
        null_resource.proxy_config,
        null_resource.proxy_additional_config,
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
            "gitlab-ctl reconfigure"
        ]
    }

    connection {
        host = element(var.admin_public_ips, 0)
        type = "ssh"
    }
}
