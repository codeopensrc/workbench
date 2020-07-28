
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
variable "lead_private_ips" { default = [] }
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

    # If having create before destroy causes this resource to run before the destroy
    # time provisioners of an instance going down.. we have a better solution to scaling down
    # As long as this doesnt cause dependency issues..
    # create_before_destroy = true

    triggers = {
        num_apps = length(keys(var.app_definitions))
        num_ips = length(var.lead_private_ips)
    }

    provisioner "remote-exec" {
        # TODO: Test if changing the group necessary or not to reading directory for nginx
        inline = [
            "echo ${join(",", var.prev_module_output)}",
            "mkdir -p /etc/nginx/conf.d",
            "chown root:gitlab-www /etc/nginx/conf.d"
        ]
    }

    ## Keep in mind, this all has to do with running the docker proxy app as proxy for our docker
    ##  apps and tieing them to consul. This will be revisted in the future (probably very near)

    ## Given below information is why we currently always proxy nginx to the last leader ip while dns resolves to the first
    # 10.1.0.0/16:  10.1.0.0  -  10.1.255.255  : Our vpc (for now) - Our security group allows this into db ports
    # 10.1.2.0/24:  10.1.2.0  -  10.1.2.255    : "Public" subnet - 255ish ips each server gets an ip on

    # What we're doing:
    # Open 4433 on 10.1.0.0/16 and proxy to last private leader ip (we dont know WHY the admin ip doesnt work
    #    when its 1admin+lead + 1lead)

    # For some reason when nginx points to admin ip (private, local, or public) and when more than 1 lead, it wont resolve swarm balanced requests to lead ip (to self are fine)
    #  but if nginx points to lead ip, it will resolve to all docker containers on admin ip just fine (also itself fine). Question is why


    ####                             Private IP        Roles                 IP          Roles
    # Given the 2 server scenario:   10.1.2.151   admin+lead+db    -     10.1.2.165      lead

    # When nginx host proxy is proxying to:
    # 10.1.2.151  admin ip    only resolves to docker containers on admin ip and NOT lead ip

    # When nginx host proxy is proxying to :
    # 10.1.2.165  lead ip     resolves to docker containers on both lead ip and admin ip


    # With a single server.  When nginx host proxy is proxying to:
    # 10.1.2.151  admin+lead ip    resolves just fine if its the only lead ip


    ## Have looked into changing the docker subnet these services are connected to but did not
    ##  find a solution given how we already open ports on all network interfaces for swarm and
    ##  even allowed all connections from all ports for the 10.1.0/16 vpc

    ## Easily something that was missed but this is as far as we got and have a "working" solution

    # TODO: Somehow need to proc changing the nginx proxy before destroying the proxy_ip node
    # NOTE: For now we do it at destroy time of the instance but its a "good enough" method and not great
    provisioner "file" {
        content = templatefile("${path.module}/templatefiles/mainproxy.tmpl", {
            root_domain_name = var.root_domain_name
            proxy_ip = element(var.lead_private_ips, length(var.lead_private_ips) - 1 )
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
