### See envs/env/main.tf locals.config
variable "config" {}

variable "stun_protos" { default = ["tcp", "udp"] }

variable "servers" {}
variable "image_size" {}
variable "image_name" { default = "" }
variable "tags" { default = [] }
variable "vpc" { default = {} }
variable "vpc_uuid" { default = "" }

terraform {
    required_providers {
        digitalocean = {
            source = "digitalocean/digitalocean"
        }
    }
    required_version = ">=0.13"
}
