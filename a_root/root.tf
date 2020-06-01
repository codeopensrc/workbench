
module "digital_ocean" {
    source             = "./digital_ocean"
    server_name_prefix = var.server_name_prefix
    active_env_provider = var.active_env_provider
    region = var.region

    do_ssh_fingerprint = var.do_ssh_fingerprint

    admin_servers = var.admin_servers
    leader_servers = var.leader_servers
    db_servers = var.db_servers
    web_servers = var.web_servers
    dev_servers = var.dev_servers
    legacy_servers = var.legacy_servers
    build_servers = var.build_servers
    mongo_servers = var.mongo_servers
    pg_servers = var.pg_servers
    redis_servers = var.redis_servers

    do_admin_size    = var.do_admin_size
    do_leader_size    = var.do_leader_size
    do_db_size    = var.do_db_size
    do_web_size    = var.do_web_size
    do_dev_size    = var.do_dev_size
    do_legacy_size    = var.do_legacy_size
    do_build_size    = var.do_build_size
    do_mongo_size    = var.do_mongo_size
    do_pg_size    = var.do_pg_size
    do_redis_size    = var.do_redis_size

    app_ips = var.app_ips
    station_ips = var.station_ips
}

module "aws" {
    source             = "./aws"
    root_domain_name = var.root_domain_name
    dns_provider = var.dns_provider
    server_name_prefix = var.server_name_prefix
    active_env_provider = var.active_env_provider
    region = var.region

    aws_key_name = var.aws_key_name
    aws_ami = var.aws_ami

    admin_servers = var.admin_servers
    leader_servers = var.leader_servers
    db_servers = var.db_servers
    web_servers = var.web_servers
    dev_servers = var.dev_servers
    legacy_servers = var.legacy_servers
    build_servers = var.build_servers
    mongo_servers = var.mongo_servers
    pg_servers = var.pg_servers
    redis_servers = var.redis_servers

    aws_admin_instance_type    = var.aws_admin_instance_type
    aws_leader_instance_type    = var.aws_leader_instance_type
    aws_db_instance_type    = var.aws_db_instance_type
    aws_web_instance_type    = var.aws_web_instance_type
    aws_dev_instance_type    = var.aws_dev_instance_type
    aws_build_instance_type    = var.aws_build_instance_type
    aws_mongo_instance_type    = var.aws_mongo_instance_type
    aws_pg_instance_type    = var.aws_pg_instance_type
    aws_redis_instance_type    = var.aws_redis_instance_type
    aws_legacy_instance_type    = var.aws_legacy_instance_type

    docker_machine_ip = var.docker_machine_ip

    admin_arecord_aliases = var.admin_arecord_aliases
    db_arecord_aliases = var.db_arecord_aliases
    leader_arecord_aliases = var.leader_arecord_aliases
    app_definitions = var.app_definitions

    app_ips = var.app_ips
    station_ips = var.station_ips
}

module "mix" {
    source             = "./mix"
    server_name_prefix = var.server_name_prefix
    active_env_provider = var.active_env_provider
    region = var.region

    aws_ecr_region   = var.aws_ecr_region
    aws_bucket_region   = var.aws_bucket_region
    aws_bucket_name   = var.aws_bucket_name

    admin_servers =  var.admin_servers
    leader_servers =  var.leader_servers
    db_servers =  var.db_servers
    web_servers =  var.web_servers
    dev_servers =  var.dev_servers
    legacy_servers =  var.legacy_servers
    build_servers =  var.build_servers
    mongo_servers =  var.mongo_servers
    pg_servers =  var.pg_servers
    redis_servers =  var.redis_servers

    # TODO: Cleaner as we introduce Azure and Google Cloud
    admin_private_ips = compact(concat(module.aws.admin_private_ip_addresses, module.digital_ocean.admin_private_ip_addresses))
    lead_private_ips = compact(concat(module.aws.lead_private_ip_addresses, module.digital_ocean.lead_private_ip_addresses))
    build_private_ips = compact(concat(module.aws.build_private_ip_addresses, module.digital_ocean.build_private_ip_addresses))
    db_private_ips = compact(concat(module.aws.db_private_ip_addresses, module.digital_ocean.db_private_ip_addresses))
    dev_private_ips = compact(concat(module.aws.dev_private_ip_addresses, module.digital_ocean.dev_private_ip_addresses))
    mongo_private_ips = compact(concat(module.aws.mongo_private_ip_addresses, module.digital_ocean.mongo_private_ip_addresses))
    pg_private_ips = compact(concat(module.aws.pg_private_ip_addresses, module.digital_ocean.pg_private_ip_addresses))
    redis_private_ips = compact(concat(module.aws.redis_private_ip_addresses, module.digital_ocean.redis_private_ip_addresses))
    web_private_ips = compact(concat(module.aws.web_private_ip_addresses, module.digital_ocean.web_private_ip_addresses))

    admin_public_ips = compact(concat(module.aws.admin_public_ip_addresses, module.digital_ocean.admin_public_ip_addresses))
    lead_public_ips = compact(concat(module.aws.lead_public_ip_addresses, module.digital_ocean.lead_public_ip_addresses))
    build_public_ips = compact(concat(module.aws.build_public_ip_addresses, module.digital_ocean.build_public_ip_addresses))
    db_public_ips = compact(concat(module.aws.db_public_ip_addresses, module.digital_ocean.db_public_ip_addresses))
    dev_public_ips = compact(concat(module.aws.dev_public_ip_addresses, module.digital_ocean.dev_public_ip_addresses))
    mongo_public_ips = compact(concat(module.aws.mongo_public_ip_addresses, module.digital_ocean.mongo_public_ip_addresses))
    pg_public_ips = compact(concat(module.aws.pg_public_ip_addresses, module.digital_ocean.pg_public_ip_addresses))
    redis_public_ips = compact(concat(module.aws.redis_public_ip_addresses, module.digital_ocean.redis_public_ip_addresses))
    web_public_ips = compact(concat(module.aws.web_public_ip_addresses, module.digital_ocean.web_public_ip_addresses))

    admin_names = compact(concat(module.aws.admin_names, module.digital_ocean.admin_names))
    lead_names = compact(concat(module.aws.lead_names, module.digital_ocean.lead_names))
    build_names = compact(concat(module.aws.build_names, module.digital_ocean.build_names))
    db_names = compact(concat(module.aws.db_names, module.digital_ocean.db_names))
    dev_names = compact(concat(module.aws.dev_names, module.digital_ocean.dev_names))
    mongo_names = compact(concat(module.aws.mongo_names, module.digital_ocean.mongo_names))
    pg_names = compact(concat(module.aws.pg_names, module.digital_ocean.pg_names))
    redis_names = compact(concat(module.aws.redis_names, module.digital_ocean.redis_names))
    web_names = compact(concat(module.aws.web_names, module.digital_ocean.web_names))

    db_ids = compact(concat(module.aws.db_ids, module.digital_ocean.db_ids))
    mongo_ids = compact(concat(module.aws.mongo_ids, module.digital_ocean.mongo_ids))
    pg_ids = compact(concat(module.aws.pg_ids, module.digital_ocean.pg_ids))
    redis_ids = compact(concat(module.aws.redis_ids, module.digital_ocean.redis_ids))

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

    db_dns    = var.db_dns
    site_dns  = var.site_dns
    admin_dns = var.admin_dns

    join_machine_id  = var.join_machine_id
    serverkey        = var.serverkey
    pg_password      = var.pg_password
    dev_pg_password  = var.dev_pg_password

    aws_bot_access_key = var.aws_bot_access_key
    aws_bot_secret_key = var.aws_bot_secret_key
    pg_read_only_pw = var.pg_read_only_pw

    deploy_key_location = var.deploy_key_location

    gitlab_backups_enabled = var.gitlab_backups_enabled
    import_gitlab = var.import_gitlab
    gitlab_runner_tokens = var.gitlab_runner_tokens
    num_gitlab_runners = var.num_gitlab_runners

    known_hosts = var.known_hosts
    app_definitions = var.app_definitions
    misc_repos = var.misc_repos

    docker_compose_version = var.docker_compose_version
    docker_engine_install_url  = var.docker_engine_install_url
    consul_version         = var.consul_version
    gitlab_version         = var.gitlab_version

    chef_server_url = var.chef_server_url
    chef_email      = var.chef_email

    root_domain_name = var.root_domain_name

    external_leaderIP = (var.active_env_provider == "digital_ocean"
        ? element(concat(module.aws.lead_public_ip_addresses, [""]), 0)
        : element(concat(module.digital_ocean.lead_public_ip_addresses, [""]), 0))
    # aws_leaderIP = "${module.aws.aws_ip}"
}
