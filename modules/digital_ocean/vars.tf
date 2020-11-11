
variable "active_env_provider" {}
variable "server_name_prefix" {}
variable "region" { default = "" }

variable "do_ssh_fingerprint" {}

variable "servers" { default = [] }

variable "admin_servers" { default = 0 }
variable "leader_servers" { default = 0 }
variable "db_servers" { default = 0 }
variable "build_servers" { default = 0 }
variable "web_servers" { default = 0 }
variable "dev_servers" { default = 0 }
variable "legacy_servers" { default = 0 }
variable "mongo_servers" { default = 0 }
variable "pg_servers" { default = 0 }
variable "redis_servers" { default = 0 }

variable "do_admin_size" { default = "s-2vcpu-8gb" }
variable "do_leader_size" { default = "s-2vcpu-4gb" }
variable "do_db_size" { default = "s-2vcpu-4gb" }
variable "do_web_size" { default = "1gb" }
variable "do_dev_size" { default = "1gb" }
variable "do_legacy_size" { default = "1gb" }
variable "do_build_size" { default = "s-2vcpu-4gb" }
variable "do_mongo_size" { default = "s-2vcpu-4gb" }
variable "do_pg_size" { default = "s-2vcpu-4gb" }
variable "do_redis_size" { default = "s-2vcpu-4gb" }

variable "app_ips" { default = [] }
variable "station_ips" { default = [] }

# ipv4_address
# terraform {
#     required_providers {
#         digitalocean = {
#             source = "digitalocean/digitalocean"
#         }
#     }
#     required_version = ">=0.13"
# }
