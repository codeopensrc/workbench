terraform {
    required_providers {
        digitalocean = {
            source = "digitalocean/digitalocean"
        }
    }
    required_version = ">=0.13"
}

### See envs/env/main.tf locals.config
variable "config" {}

variable "stun_protos" { default = ["tcp", "udp"] }

variable "servers" {}
variable "image_name" {}
variable "image_size" {}
variable "tags" {}
variable "vpc_uuid" {}
variable "admin_ip_public" { default = ""}
variable "admin_ip_private" { default = ""}
variable "consul_lan_leader_ip" { default = ""}
