
variable "server_name_prefix" {}
variable "active_env_provider" {}
variable "root_domain_name" {}
variable "region" { default = "" }
variable "aws_ecr_region" { default = "" }
variable "aws_bucket_region" { default = "" }
variable "aws_bucket_name" { default = "" }

variable "admin_servers" { default = 0 }
variable "leader_servers" { default = 0 }
variable "db_servers" { default = 0 }
variable "web_servers" { default = 0 }
variable "dev_servers" { default = 0 }
variable "build_servers" { default = 0 }
variable "mongo_servers" { default = 0 }
variable "pg_servers" { default = 0 }
variable "redis_servers" { default = 0 }
variable "legacy_servers" { default = 0 }


# Cloudflare/dns variables _should_ be optional to modify DNS settings on cloudflare
# At this time, they are required until properly refactored
# UPD: Cloudflare should no longer be needed but some dns variables still need to be populated until refactor

variable "cloudflare_email" { default = "" }
variable "cloudflare_auth_key" { default = "" }
variable "cloudflare_zone_id" { default = "" }

variable "mattermost_subdomain" {}
variable "wekan_subdomain" {}

variable "change_db_dns" {}
variable "change_site_dns" {}
variable "change_admin_dns" {}

variable "db_backups_enabled" {}
variable "run_service_enabled" {}
variable "send_logs_enabled" {}
variable "send_jsons_enabled" {}
variable "import_dbs" {}

variable "dbs_to_import" {
    type = list(object({ type=string, aws_bucket=string, aws_region=string,
        dbname=string, import=string, fn=string }))
}

variable "db_dns" { type = map(object({ url=string, dns_id=string, zone_id=string })) }
variable "site_dns" { type = list(object({ url=string, dns_id=string, zone_id=string })) }
variable "admin_dns" { type = list(object({ url=string, dns_id=string, zone_id=string })) }

variable "join_machine_id" { default = "" }
variable "serverkey" {}
variable "pg_password" {}
variable "dev_pg_password" {}

variable "aws_bot_access_key" { default = "" }
variable "aws_bot_secret_key" { default = "" }
variable "pg_read_only_pw" { default = "" }

variable "docker_compose_version" {}
variable "docker_engine_install_url" {}
variable "consul_version" {}
variable "gitlab_version" {}

variable "deploy_key_location" {}

variable "gitlab_backups_enabled" { default = "" }
variable "import_gitlab" { default = "" }
variable "gitlab_runner_tokens" { type = map(string) }
variable "num_gitlab_runners" { default = 0 }

variable "known_hosts" { default = [] }

variable "app_definitions" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string, docker_registry=string, docker_registry_image=string,
        docker_registry_url=string, docker_registry_user=string, docker_registry_pw=string, service_name=string,
        green_service=string, blue_service=string, default_active=string, create_subdomain=string, subdomain_name=string }))
}
variable "misc_repos" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string, docker_registry_image=string,
        docker_service_name=string, consul_service_name=string, folder_location=string,
        logs_prefix=string, email_image=string
    }))
}

variable "gitlab_server_url" { default = "" }
variable "chef_email" { default = "" }


variable "admin_private_ips" { type = list(string) }
variable "lead_private_ips" { type = list(string) }
variable "db_private_ips" { type = list(string) }
# variable "build_private_ips" { type = list(string) }
# variable "dev_private_ips" { type = list(string) }
# variable "mongo_private_ips" { type = list(string) }
# variable "pg_private_ips" { type = list(string) }
# variable "redis_private_ips" { type = list(string) }
# variable "web_private_ips" { type = list(string) }

variable "admin_public_ips" { type = list(string) }
variable "lead_public_ips" { type = list(string) }
variable "db_public_ips" { type = list(string) }
# variable "build_public_ips" { type = list(string) }
# variable "dev_public_ips" { type = list(string) }
# variable "mongo_public_ips" { type = list(string) }
# variable "pg_public_ips" { type = list(string) }
# variable "redis_public_ips" { type = list(string) }
# variable "web_public_ips" { type = list(string) }

variable "admin_names" { type = list(string) }
variable "lead_names" { type = list(string) }
variable "db_names" { type = list(string) }
# variable "build_names" { type = list(string) }
# variable "dev_names" { type = list(string) }
# variable "mongo_names" { type = list(string) }
# variable "pg_names" { type = list(string) }
# variable "redis_names" { type = list(string) }
# variable "web_names" { type = list(string) }

variable "db_ids" { type = list(string) }
# variable "mongo_ids" { type = list(string) }
# variable "pg_ids" { type = list(string) }
# variable "redis_ids" { type = list(string) }

locals {

    redis_dbs = [
        for db in var.dbs_to_import:
        db.dbname
        if db.type == "redis" && db.import == "true"
    ]
    pg_dbs = [
        for db in var.dbs_to_import:
        db.dbname
        if db.type == "pg" && db.import == "true"
    ]
    mongo_dbs = [
        for db in var.dbs_to_import:
        db.dbname
        if db.type == "mongo" && db.import == "true"
    ]
    pg_fn = {
        for db in var.dbs_to_import:
        db.type => db.fn
        if db.type == "pg" && db.import == "true"
    }

    docker_service_name   = contains(keys(var.misc_repos), "service") ? lookup(var.misc_repos["service"], "docker_service_name" ) : ""
    consul_service_name   = contains(keys(var.misc_repos), "service") ? lookup(var.misc_repos["service"], "consul_service_name" ) : ""
    folder_location       = contains(keys(var.misc_repos), "service") ? lookup(var.misc_repos["service"], "folder_location" ) : ""
    logs_prefix           = contains(keys(var.misc_repos), "service") ? lookup(var.misc_repos["service"], "logs_prefix" ) : ""
    email_image           = contains(keys(var.misc_repos), "service") ? lookup(var.misc_repos["service"], "email_image" ) : ""
    service_repo_name     = contains(keys(var.misc_repos), "service") ? lookup(var.misc_repos["service"], "repo_name" ) : ""

    # Simple logic for now. One datacenter/provider per env. Eventually something like AWS east coast and DO west coast connected would be cool
    consul_lan_leader_ip = var.active_env_provider == "aws" ? element(concat(var.admin_private_ips, [""]), 0) : element(concat(var.admin_public_ips, [""]), 0)

    consul_admin_adv_addresses = var.active_env_provider == "aws" ? var.admin_private_ips : var.admin_public_ips
    consul_lead_adv_addresses = var.active_env_provider == "aws" ? var.lead_private_ips : var.lead_public_ips
    consul_db_adv_addresses = var.active_env_provider == "aws" ? var.db_private_ips : var.db_public_ips

    # consul_build_adv_addresses = var.active_env_provider == "aws" ? var.build_private_ips : var.build_public_ips
    # consul_dev_adv_addresses = var.active_env_provider == "aws" ? var.dev_private_ips : var.dev_public_ips
    # consul_mongo_adv_addresses = var.active_env_provider == "aws" ? var.mongo_private_ips : var.mongo_public_ips
    # consul_pg_adv_addresses = var.active_env_provider == "aws" ? var.pg_private_ips : var.pg_public_ips
    # consul_redis_adv_addresses = var.active_env_provider == "aws" ? var.redis_private_ips : var.redis_public_ips
    # consul_web_adv_addresses = var.active_env_provider == "aws" ? var.web_private_ips : var.web_public_ips

}

# variable "aws_leaderIP" { default = "" }
variable "external_leaderIP" { default = "" }
