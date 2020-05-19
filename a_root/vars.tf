variable "ubuntu_ver" { default = "16.04"}

variable "active_env_provider" { default = "" }
variable "region" { default = "" }
variable "server_name_prefix" {}
variable "root_domain_name" {}

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

# digital ocean
variable "do_ssh_fingerprint" {}

variable "do_admin_size" { default = "" }
variable "do_leader_size" { default = "" }
variable "do_db_size" { default = "" }
variable "do_web_size" { default = "" }
variable "do_dev_size" { default = "" }
variable "do_build_size" { default = "" }
variable "do_mongo_size" { default = "" }
variable "do_pg_size" { default = "" }
variable "do_redis_size" { default = "" }
variable "do_legacy_size" { default = "" }


# aws
variable "aws_key_name" {}
variable "aws_ami" { default = "" }
variable "aws_ecr_region" { default = "" }
variable "aws_bucket_region" { default = "" }
variable "aws_bucket_name" { default = "" }

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


variable "dns_provider" { default = "" }

# Cloudflare/dns variables _should_ be optional to modify DNS settings on cloudflare
# At this time, they are required until properly refactored
# UPD: Cloudflare should no longer be needed but some dns variables still need to be populated until refactor

variable "cloudflare_email" { default = "" }
variable "cloudflare_auth_key" { default = "" }
variable "cloudflare_zone_id" { default = "" }

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
        dbname=string, import=string }))
}

variable "db_dns" { type = map(object({ url=string, dns_id=string, zone_id=string })) }
variable "site_dns" { type = list(object({ url=string, dns_id=string, zone_id=string })) }
variable "admin_dns" { type = list(object({ url=string, dns_id=string, zone_id=string })) }

variable "admin_arecord_aliases" { type = list }
variable "db_arecord_aliases" { type = list }
variable "leader_arecord_aliases" { type = list }

variable "join_machine_id" { default = "" }
variable "serverkey" {}
variable "pg_password" {}
variable "dev_pg_password" {}
variable "docker_machine_ip" {}

variable "aws_bot_access_key" { default = "" }
variable "aws_bot_secret_key" { default = "" }
variable "pg_md5_password" { default = "" }
variable "pg_read_only_pw" { default = "" }

variable "docker_compose_version" {}
variable "docker_engine_version" {}
variable "consul_version" {}
variable "gitlab_version" {}

variable "deploy_key_location" {}

variable "backup_gitlab" { default = "" }
variable "import_gitlab" { default = "" }
variable "gitlab_runner_tokens" { type = map(string) }
variable "num_gitlab_runners" { default = 0 }

variable "app_definitions" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string, docker_registry=string, docker_registry_image=string,
        docker_registry_url=string, docker_registry_user=string, docker_registry_pw=string, service_name=string,
        green_service=string, blue_service=string, default_active=string, create_subdomain=string }))
}
variable "misc_repos" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string }))
}

variable "chef_server_url" { default = "" }
variable "chef_server_http_port" { default = "" }
variable "chef_server_https_port" { default = "" }

variable "chef_remote_dir" { default = "" }
variable "chef_local_dir" { default = "" }

variable "chef_user" { default = "" }
variable "chef_fn" { default = "" }
variable "chef_ln" { default = "" }
variable "chef_email" { default = "" }
variable "chef_pw" { default = "" }

variable "chef_org_short" { default = "" }
variable "chef_org_full" { default = "" }
variable "chef_org_user" { default = "" }

variable "chef_server_ver" { default = "" }
variable "chef_dk_ver" { default = "" }
variable "chef_client_ver" { default = "" }

variable "do_leaderIP" { default = ""}
variable "aws_leaderIP" { default = "" }
variable "external_chef_id" { default = "" }
