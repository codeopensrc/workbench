####### VARIABLES INSIDE MODULES SHOULD NOT BE MODIFIED
####### VARIABLES INSIDE MODULES SHOULD NOT BE MODIFIED
####### VARIABLES INSIDE MODULES SHOULD NOT BE MODIFIED
####### VARIABLES INSIDE MODULES SHOULD NOT BE MODIFIED
#  ONLY THE SIZE OF THE SERVERS AND THAT SHOULD BE DONE
#  WITH CAUTION AS IT REBOOTS ALL SERVERS BEING RESIZED

# Also ONLY if you are commenting/uncommenting the following:
# do_leaderIP
# aws_leaderIP
# external_chef_id

module "root" {
    source             = "../../../a_root"
    server_name_prefix = var.server_name_prefix

    active_env_provider = var.active_env_provider
    dns_provider        = var.dns_provider

    # Address this
    # Address this
    # TEMP
    db_dns           = var.active_env_provider == "digital_ocean" ? var.do_db_dns : var.aws_db_dns
    region           = var.active_env_provider == "digital_ocean" ? var.do_region : var.aws_region_alias
    pg_password      = var.pg_password
    dev_pg_password  = var.dev_pg_password
    pg_read_only_pw  = var.pg_read_only_pw

    aws_bot_access_key = var.aws_bot_access_key
    aws_bot_secret_key = var.aws_bot_secret_key
    pg_md5_password = var.pg_md5_password
    docker_machine_ip = var.docker_machine_ip
    # Address this
    # Address this

    admin_servers = var.admin
    leader_servers = var.leader
    db_servers = var.db
    web_servers = var.web
    dev_servers = var.dev
    legacy_servers = var.legacy
    build_servers = var.build
    mongo_servers = var.mongo
    pg_servers = var.pg
    redis_servers = var.redis

    do_ssh_fingerprint = var.do_ssh_fingerprint

    do_admin_size    = var.do_admin_size
    do_leader_size    = var.do_admin_size
    do_db_size    = var.do_admin_size
    do_web_size    = var.do_web_size
    do_dev_size    = var.do_dev_size
    do_legacy_size    = var.do_legacy_size
    do_build_size    = var.do_build_size
    do_mongo_size    = var.do_mongo_size
    do_pg_size    = var.do_pg_size
    do_redis_size    = var.do_redis_size

    aws_bucket_name = var.aws_bucket_name
    aws_bucket_region = var.aws_bucket_region
    aws_key_name       = var.aws_key_name
    aws_ami    = var.aws_ami
    aws_ecr_region   = var.aws_ecr_region

    aws_admin_instance_type = var.aws_admin_instance_type
    aws_leader_instance_type = var.aws_leader_instance_type
    aws_db_instance_type = var.aws_db_instance_type
    aws_web_instance_type = var.aws_web_instance_type
    aws_build_instance_type = var.aws_build_instance_type
    aws_mongo_instance_type = var.aws_mongo_instance_type
    aws_pg_instance_type = var.aws_pg_instance_type
    aws_redis_instance_type = var.aws_redis_instance_type

    cloudflare_email    = var.cloudflare_email
    cloudflare_auth_key = var.cloudflare_auth_key
    cloudflare_zone_id  = var.cloudflare_zone_id

    change_db_dns    = var.change_db_dns
    change_site_dns  = var.change_site_dns
    change_admin_dns = var.change_admin_dns

    db_backups_enabled  = var.db_backups_enabled
    run_service_enabled = var.run_service_enabled
    send_logs_enabled   = var.send_logs_enabled
    send_jsons_enabled  = var.send_jsons_enabled
    import_dbs          = var.import_dbs
    dbs_to_import       = var.dbs_to_import

    site_dns  = var.site_dns
    admin_dns = var.admin_dns

    admin_arecord_aliases = var.admin_arecord_aliases
    db_arecord_aliases = var.db_arecord_aliases
    leader_arecord_aliases = var.leader_arecord_aliases

    join_machine_id  = var.join_machine_id
    serverkey        = var.serverkey

    deploy_key_location = var.deploy_key_location

    backup_gitlab = var.backup_gitlab
    import_gitlab = var.import_gitlab
    gitlab_runner_tokens = var.gitlab_runner_tokens
    num_gitlab_runners = var.num_gitlab_runners

    app_definitions = var.app_definitions
    misc_repos      = var.misc_repos

    docker_compose_version = var.docker_compose_version
    docker_engine_version  = var.docker_engine_version
    consul_version         = var.consul_version
    gitlab_version         = var.gitlab_version

    chef_server_url = var.chef_server_url
    chef_server_http_port = var.chef_server_http_port
    chef_server_https_port = var.chef_server_https_port

    chef_remote_dir = var.chef_remote_dir
    chef_local_dir  = var.chef_local_dir
    chef_user       = var.chef_user
    chef_fn         = var.chef_fn
    chef_ln         = var.chef_ln
    chef_email      = var.chef_email
    chef_pw         = var.chef_pw
    chef_org_short  = var.chef_org_short
    chef_org_full   = var.chef_org_full
    chef_org_user   = var.chef_org_user
    chef_server_ver = var.chef_server_ver
    chef_dk_ver     = var.chef_dk_ver
    chef_client_ver = var.chef_client_ver

    root_domain_name = var.root_domain_name
    # Doesn't wait for aws leader to be created, but aws_ip is created very quickly
    # aws_leaderIP = "${module.aws.aws_ip}"
    # external_chef_id = "${module.aws.aws_chef_id}"
}
