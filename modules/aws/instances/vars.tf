### See envs/env/main.tf locals.config
variable "config" {}

variable "stun_protos" { default = ["tcp", "udp"] }

variable "servers" {}
variable "image_size" {}
variable "image_name" { default = "" }
variable "tags" { default = [] }
variable "vpc" { default = {} }
variable "vpc_uuid" { default = "" }
variable "admin_ip_public" { default = "" }
variable "admin_ip_private" { default = "" }
variable "consul_lan_leader_ip" { default = "" }
