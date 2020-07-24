
variable "servers" {}
variable "root_domain_name" { default = "" }
variable "public_ips" {
    type = list(string)
    default = []
}
variable "lead_public_ips" {
    type = list(string)
    default = []
}
variable "https_port" {}
variable "cert_port" {}
variable "app_definitions" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string, docker_registry=string, docker_registry_image=string,
        docker_registry_url=string, docker_registry_user=string, docker_registry_pw=string, service_name=string,
        green_service=string, blue_service=string, default_active=string, create_subdomain=string, subdomain_name=string }))
}

variable "prev_module_output" {}



resource "null_resource" "proxy_config" {
    count = var.servers

    triggers = {
        wait_for_prev_module = "${join(",", var.prev_module_output)}"
        num_apps = length(keys(var.app_definitions))
    }

    provisioner "remote-exec" {
        # TODO: Test if changing the group necessary or not to reading directory for nginx
        inline = [
            "mkdir -p /etc/nginx/conf.d",
            "chown root:gitlab-www /etc/nginx/conf.d"
        ]
    }

    provisioner "file" {
        content = templatefile("${path.module}/templatefiles/mainproxy.tmpl", {
            root_domain_name = var.root_domain_name
            proxy_ip = contains(var.lead_public_ips, element(var.public_ips, count.index)) ? "127.0.0.1" : element(var.lead_public_ips, 0)
            https_port = contains(var.lead_public_ips, element(var.public_ips, count.index)) ? var.https_port : 443
            cert_port = var.cert_port
            subdomains = [
                for HOST in var.app_definitions:
                format("%s.%s", HOST.subdomain_name, var.root_domain_name)
                if HOST.create_subdomain == "true"
            ]
        })
        destination = "/etc/nginx/conf.d/proxy.conf"
    }

    provisioner "remote-exec" {
        ## TODO: Because of this convenience for config on app change, it has to be run after gitlab is installed
        inline = [ "gitlab-ctl reconfigure" ]
    }

    connection {
        host = element(var.public_ips, count.index)
        type = "ssh"
    }
}

output "output" {
    depends_on = [
        proxy_config,
    ]
    value = null_resource.proxy_config.*.id
}
