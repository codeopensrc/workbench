terraform {
  required_version = ">= 0.12"
}
variable "server_name_prefix" {}
variable "active_env_provider" {}
variable "root_domain_name" {}
variable "additional_domains" {}
variable "region" { default = "" }
variable "vpc_private_iface" { default = "" }
variable "aws_ecr_region" { default = "" }
variable "s3alias" { default = "" }
variable "s3bucket" { default = "" }
variable "do_spaces_region" { default = "" }
variable "do_spaces_access_key" { default = "" }
variable "do_spaces_secret_key" { default = "" }

variable "servers" { default = [] }

variable "mattermost_subdomain" {}
variable "wekan_subdomain" {}
variable "additional_ssl" {}
variable "sendgrid_apikey" { default = "" }
variable "sendgrid_domain" { default = "" }

variable "import_dbs" {}
variable "install_unity3d" { default = false }

variable "dbs_to_import" {
    type = list(object({ type=string, s3bucket=string, s3alias=string,
        dbname=string, import=string, backups_enabled=string, fn=string }))
}
variable "redis_dbs" { default = [] }
variable "pg_dbs" { default = [] }
variable "mongo_dbs" { default = [] }

variable "serverkey" {}
variable "pg_password" {}
variable "dev_pg_password" {}

variable "aws_bot_access_key" { default = "" }
variable "aws_bot_secret_key" { default = "" }

variable "gitlab_backups_enabled" { default = "" }
variable "import_gitlab" { default = "" }
variable "import_gitlab_version" { default = "" }
variable "gitlab_runner_tokens" { type = map(string) }
variable "num_gitlab_runners" { default = 0 }

variable "app_definitions" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string, docker_registry=string, docker_registry_image=string,
        docker_registry_url=string, docker_registry_user=string, docker_registry_pw=string, service_name=string,
        green_service=string, blue_service=string, default_active=string,
        create_dns_record=string, create_dev_dns=string, create_ssl_cert=string, subdomain_name=string,
        use_custom_backup=string, custom_backup_file=string, backup_frequency=string,
        use_custom_restore=string, custom_restore_file=string, custom_init=string, custom_vars=string
    }))
}
variable "misc_repos" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string, docker_registry_image=string,
        docker_service_name=string, consul_service_name=string, folder_location=string,
        logs_prefix=string, email_image=string
    }))
}

variable "contact_email" { default = "" }
variable "use_gpg" { default = false }
variable "bot_gpg_name" { default = "" }
variable "bot_gpg_passphrase" { default = "" }

variable "admin_private_ips" { type = list(string) }
variable "lead_private_ips" { type = list(string) }
variable "db_private_ips" { type = list(string) }
variable "build_private_ips" { type = list(string) }

variable "admin_public_ips" { type = list(string) }
variable "lead_public_ips" { type = list(string) }
variable "db_public_ips" { type = list(string) }
variable "build_public_ips" { type = list(string) }

variable "admin_names" { type = list(string) }
variable "lead_names" { type = list(string) }
variable "db_names" { type = list(string) }
variable "build_names" { type = list(string) }

variable "db_ids" { type = list(string) }
variable "ansible_hosts" { type = list(object({ name=string, roles=list(string), ip=string })) }
variable "ansible_hostfile" { default = "" }

locals {
    # TODO: Turn these into maps to reference by key
    # reduce count attribute if roles contains same key
    server_count = sum(tolist([
        for SERVER in var.servers:
        SERVER.count
    ]))
    lead_servers = sum(concat([0], tolist([
        for SERVER in var.servers:
        SERVER.count
        if contains(SERVER.roles, "lead")
    ])))
    admin_servers = sum(concat([0], tolist([
        for SERVER in var.servers:
        SERVER.count
        if contains(SERVER.roles, "admin")
    ])))
    db_servers = sum(concat([0], tolist([
        for SERVER in var.servers:
        SERVER.count
        if contains(SERVER.roles, "db")
    ])))
    build_servers = sum(concat([0], tolist([
        for SERVER in var.servers:
        SERVER.count
        if contains(SERVER.roles, "build")
    ])))


    all_private_ips = distinct(concat(var.admin_private_ips, var.lead_private_ips, var.db_private_ips,
        var.build_private_ips))

    all_public_ips = distinct(concat(var.admin_public_ips, var.lead_public_ips, var.db_public_ips,
        var.build_public_ips))

    all_names = distinct(concat(var.admin_names, var.lead_names, var.db_names, var.build_names))

    ## Allows db with lead
    is_only_leader_count = sum(concat([0], tolist([
        for SERVER in var.servers:
        SERVER.count
        if contains(SERVER.roles, "lead") && !contains(SERVER.roles, "admin")
    ])))
    ## Allows db with lead
    is_only_db_count = sum(concat([0], tolist([
        for SERVER in var.servers:
        SERVER.count
        if contains(SERVER.roles, "db") && !contains(SERVER.roles, "admin")
    ])))
    is_only_build_count = sum(concat([0], tolist([
        for SERVER in var.servers:
        SERVER.count
        if contains(SERVER.roles, "build") && length(SERVER.roles) == 1
    ])))
    is_not_admin_count = sum([local.is_only_leader_count, local.is_only_db_count, local.is_only_build_count])

}

## for_each example
# locals{
#     images = { for v in var.images : v => v }
# }
# resource "aws_ecr_repository" "default" {
#   for_each = local.images
#   name  = "${each.key}"
# }

# variable "aws_leaderIP" { default = "" }
#variable "external_leaderIP" { default = "" }
