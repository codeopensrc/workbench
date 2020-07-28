# ####### VARIABLES INSIDE MODULES SHOULD NOT BE MODIFIED
# ####### VARIABLES INSIDE MODULES SHOULD NOT BE MODIFIED
# ####### VARIABLES INSIDE MODULES SHOULD NOT BE MODIFIED
# ####### VARIABLES INSIDE MODULES SHOULD NOT BE MODIFIED
# #  ONLY THE SIZE OF THE SERVERS AND THAT SHOULD BE DONE
# #  WITH CAUTION AS IT REBOOTS ALL SERVERS BEING RESIZED
#
# # Also ONLY if you are commenting/uncommenting the following:
# # do_leaderIP
# # aws_leaderIP
#
# module "root" {
#     source             = "../../../a_root"
#     server_name_prefix = var.server_name_prefix
#
#     active_env_provider = var.active_env_provider
#     dns_provider        = var.dns_provider
#     use_packer_image    = var.use_packer_image
#     build_packer_image  = var.build_packer_image
#     aws_region          = var.aws_region
#     aws_access_key = var.aws_access_key
#     aws_secret_key = var.aws_secret_key
#     packer_default_amis = var.packer_default_amis
#
#     # Address this
#     # Address this
#     # TEMP
#     region           = var.active_env_provider == "digital_ocean" ? var.do_region : var.aws_region_alias
#     pg_password      = var.pg_password
#     dev_pg_password  = var.dev_pg_password
#     pg_read_only_pw  = var.pg_read_only_pw
#
#     aws_bot_access_key = var.aws_bot_access_key
#     aws_bot_secret_key = var.aws_bot_secret_key
#     docker_machine_ip = var.docker_machine_ip
#     # Address this
#     # Address this
#
#     servers = var.servers
#
#     do_ssh_fingerprint = var.do_ssh_fingerprint
#
#     aws_bucket_name = var.aws_bucket_name
#     aws_bucket_region = var.aws_bucket_region
#     aws_key_name       = var.aws_key_name
#     aws_ecr_region   = var.aws_ecr_region
#
#     cloudflare_email    = var.cloudflare_email
#     cloudflare_auth_key = var.cloudflare_auth_key
#     cloudflare_zone_id  = var.cloudflare_zone_id
#
#     mattermost_subdomain  = var.mattermost_subdomain
#     wekan_subdomain  = var.wekan_subdomain
#
#     db_backups_enabled  = var.db_backups_enabled
#     run_service_enabled = var.run_service_enabled
#     send_logs_enabled   = var.send_logs_enabled
#     send_jsons_enabled  = var.send_jsons_enabled
#     import_dbs          = var.import_dbs
#     dbs_to_import       = var.dbs_to_import
#
#     admin_arecord_aliases = var.admin_arecord_aliases
#     db_arecord_aliases = var.db_arecord_aliases
#     leader_arecord_aliases = var.leader_arecord_aliases
#
#     join_machine_id  = var.join_machine_id
#     serverkey        = var.serverkey
#
#     deploy_key_location = var.deploy_key_location
#
#     gitlab_backups_enabled = var.gitlab_backups_enabled
#     import_gitlab = var.import_gitlab
#     gitlab_runner_tokens = var.gitlab_runner_tokens
#     num_gitlab_runners = var.num_gitlab_runners
#
#     app_ips = var.app_ips
#     station_ips = var.station_ips
#     known_hosts = var.known_hosts
#     app_definitions = var.app_definitions
#     misc_repos      = var.misc_repos
#
#     redis_version = var.redis_version
#     docker_compose_version = var.docker_compose_version
#     docker_engine_install_url  = var.docker_engine_install_url
#     consul_version         = var.consul_version
#     gitlab_version         = var.gitlab_version
#
#     gitlab_server_url = var.gitlab_server_url
#     chef_email      = var.chef_email
#
#     root_domain_name = var.root_domain_name
#     # Doesn't wait for aws leader to be created, but aws_ip is created very quickly
#     # aws_leaderIP = "${module.aws.aws_ip}"
# }
