terraform {
    required_providers {
        digitalocean = {
            source = "digitalocean/digitalocean"
        }
    }
    required_version = ">=0.13"
}

### All in config{}
# variable "root_domain_name" {}
# variable "local_ssh_key_file" {}
# variable "active_env_provider" {}
# variable "server_name_prefix" {}
# variable "region" { default = "" }
# variable "aws_key_name" {}
# variable "packer_image_id" { default = "" }
# variable "servers" { default = [] }
# variable "downsize" { default = false }
# variable "stun_port" { default = "" }
# variable "docker_machine_ip" { default = "" }
# variable "admin_arecord_aliases" { type = list }
# variable "db_arecord_aliases" { type = list }
# variable "leader_arecord_aliases" { type = list }
# variable "offsite_arecord_aliases" { type = list }
# variable "additional_domains" { type = map }
# variable "additional_ssl" { type = list }
# variable "app_definitions" {
#     type = map(object({ pull=string, stable_version=string, use_stable=string,
#         repo_url=string, repo_name=string, docker_registry=string, docker_registry_image=string,
#         docker_registry_url=string, docker_registry_user=string, docker_registry_pw=string, service_name=string,
#         green_service=string, blue_service=string, default_active=string,
#         create_dns_record=string, create_dev_dns=string, create_ssl_cert=string, subdomain_name=string
#     }))
# }
# variable "cidr_block" {}
# variable "app_ips" { default = [] }
# variable "station_ips" { default = [] }
# variable "do_ssh_fingerprint" {}
# variable "do_region" {}
# variable "aws_region" {}
# variable "aws_access_key" {}
# variable "aws_secret_key" {}
# variable "do_token" {}
# variable "packer_config" {}
# variable "misc_cname" {}
variable "config" {}
variable "stun_protos" { default = ["tcp", "udp"] }

variable "servers" {}
variable "image_name" {}
variable "image_size" {}
variable "tags" {}
variable "vpc_uuid" {}
variable "admin_ip_public" { default = ""}
variable "admin_ip_private" { default = ""}
