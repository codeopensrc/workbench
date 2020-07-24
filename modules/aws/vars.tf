
variable "root_domain_name" {}

variable "dns_provider" {}
variable "active_env_provider" {}
variable "server_name_prefix" {}
variable "region" { default = "" }

variable "aws_key_name" {}
variable "use_packer_image" { default = "" }
variable "packer_image_id" { default = "" }

variable "servers" { default = [] }

variable "docker_machine_ip" { default = "" }

variable "admin_arecord_aliases" { type = list }
variable "db_arecord_aliases" { type = list }
variable "leader_arecord_aliases" { type = list }

variable "app_definitions" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string, docker_registry=string, docker_registry_image=string,
        docker_registry_url=string, docker_registry_user=string, docker_registry_pw=string, service_name=string,
        green_service=string, blue_service=string, default_active=string, create_subdomain=string, subdomain_name=string }))
}

variable "app_ips" { default = [] }
variable "station_ips" { default = [] }

locals {
    ## Loop through servers and change name if it does not contain admin
    ## TODO: Better handling how the role based name is added to machine name
    server_names = [
        for app in var.servers:
        element(app.roles, 0)
    ]
}
