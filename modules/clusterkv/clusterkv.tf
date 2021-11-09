variable "app_definitions" { default = [] }
variable "additional_ssl" { default = [] }
variable "root_domain_name" { default = "" }
variable "serverkey" { default = "" }
variable "pg_password" { default = "" }
variable "dev_pg_password" { default = "" }

variable "ansible_hostfile" { default = "" }

###### NOTE: Old comment/note below, probably not even applicable anymore with kubernetes and canary deployments etc.
###### Can do canary, blue-green, or simply implement rollbacks if X% issues start happening

#### TODO: Find a way to gradually migrate from blue -> green and vice versa vs
####   just sending all req suddenly from blue to green
#### This way if the deployment was scuffed, it only affects X% of users whether
####   pre-determined  20/80 split etc. or part of slow rollout
#### TODO: We already register a check/service with consul.. maybe have the app also
####   register its consul endpoints as well?


## NOTE: Only thing for this is consul needs to be installed
## Not really sure if we just fail if no consul/cluster leader or try checking and print detailed info if fail
resource "null_resource" "add_consul_kv" {
    triggers = {
        num_apps = length(keys(var.app_definitions))
        additional_ssl = join(",", [
            for app in var.additional_ssl:
            app.service_name
            if app.create_ssl_cert == true
        ])
    }

    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ${path.module}/playbooks/clusterkv.yml -i ${var.ansible_hostfile} --extra-vars \
                'app_definitions=${jsonencode(var.app_definitions)} additional_ssl=${jsonencode(var.additional_ssl)} \
                root_domain_name=${var.root_domain_name} serverkey=${var.serverkey} pg_password=${var.pg_password} dev_pg_password=${var.dev_pg_password}'
        EOF
    }
}

#resource "null_resource" "add_proxy_hosts" {
#
#    #### TODO: Find a way to gradually migrate from blue -> green and vice versa vs
#    ####   just sending all req suddenly from blue to green
#    #### This way if the deployment was scuffed, it only affects X% of users whether
#    ####   pre-determined  20/80 split etc. or part of slow rollout
#    #### TODO: We already register a check/service with consul.. maybe have the app also
#    ####   register its consul endpoints as well?
#
#    #triggers = {
#    #    num_apps = length(keys(var.app_definitions))
#    #    additional_ssl = join(",", [
#    #        for app in var.additional_ssl:
#    #        app.service_name
#    #        if app.create_ssl_cert == true
#    #    ])
#    #}
#
#    provisioner "file" {
#        content = <<-EOF
#            
#            consul kv delete -recurse applist
#
#            %{ for APP in var.app_definitions }
#
#                SUBDOMAIN_NAME=${APP["subdomain_name"]};
#                SERVICE_NAME=${APP["service_name"]};
#                GREEN_SERVICE=${APP["green_service"]};
#                BLUE_SERVICE=${APP["blue_service"]};
#                DEFAULT_ACTIVE=${APP["default_active"]};
#
#                consul kv put apps/$SUBDOMAIN_NAME/green $GREEN_SERVICE
#                consul kv put apps/$SUBDOMAIN_NAME/blue $BLUE_SERVICE
#                consul kv put apps/$SUBDOMAIN_NAME/active $DEFAULT_ACTIVE
#                consul kv put applist/$SERVICE_NAME $SUBDOMAIN_NAME
#
#            %{ endfor }
#
#            %{ for APP in var.additional_ssl }
#
#                SUBDOMAIN_NAME=${APP["subdomain_name"]};
#                SERVICE_NAME=${APP["service_name"]};
#
#                consul kv put applist/$SERVICE_NAME $SUBDOMAIN_NAME
#
#                ### This is temporary
#                consul kv put apps/$SUBDOMAIN_NAME/green 172.17.0.1:31000
#                consul kv put apps/$SUBDOMAIN_NAME/blue _dev
#                consul kv put apps/$SUBDOMAIN_NAME/active green
#
#                consul kv put apps/$SUBDOMAIN_NAME.beta/green 172.17.0.1:31000
#                consul kv put apps/$SUBDOMAIN_NAME.beta/blue _dev
#                consul kv put apps/$SUBDOMAIN_NAME.beta/active green
#            %{ endfor }
#
#            consul kv put domainname ${var.root_domain_name}
#            consul kv put serverkey ${var.serverkey}
#            consul kv put PG_PASSWORD ${var.pg_password}
#            consul kv put DEV_PG_PASSWORD ${var.dev_pg_password}
#            exit 0
#        EOF
#        destination = "/tmp/consulkeys.sh"
#    }
#
#    provisioner "remote-exec" {
#        inline = [
#            "chmod +x /tmp/consulkeys.sh",
#            "/tmp/consulkeys.sh",
#            "rm /tmp/consulkeys.sh",
#        ]
#    }
#    connection {
#        host = element(concat(var.admin_public_ips, var.lead_public_ips), 0)
#        type = "ssh"
#    }
#}
