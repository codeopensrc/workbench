
variable "root_domain_name" {}

variable "dns_provider" {}
variable "active_env_provider" {}
variable "server_name_prefix" {}
variable "region" { default = "" }

variable "aws_key_name" {}
variable "aws_ami" { default = "" }

variable "admin_servers" {}
variable "leader_servers" {}
variable "db_servers" {}
variable "build_servers" {}
variable "web_servers" {}
variable "dev_servers" {}
variable "legacy_servers" {}
variable "mongo_servers" {}
variable "pg_servers" {}
variable "redis_servers" {}

variable "aws_admin_instance_type" { default = "" }
variable "aws_leader_instance_type" { default = "" }
variable "aws_db_instance_type" { default = "" }
variable "aws_web_instance_type" { default = "" }
variable "aws_dev_instance_type" { default = "" }
variable "aws_build_instance_type" { default = "" }
variable "aws_mongo_instance_type" { default = "" }
variable "aws_pg_instance_type" { default = "" }
variable "aws_redis_instance_type" { default = "" }
variable "aws_legacy_instance_type" { default = "" }

variable "docker_machine_ip" { default = "" }

variable "admin_arecord_aliases" { type = list }
variable "db_arecord_aliases" { type = list }
variable "leader_arecord_aliases" { type = list }

variable "app_definitions" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string, docker_registry=string, docker_registry_image=string,
        docker_registry_url=string, docker_registry_user=string, docker_registry_pw=string, service_name=string,
        green_service=string, blue_service=string, default_active=string, create_subdomain=string }))
}
