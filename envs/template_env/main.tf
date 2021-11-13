###################################
####### Variables inside modules not intended to be modified
###################################
#### Only apps.tf, credentials.tf, and vars.tf should be modified
###################################

# `terraform output` for name and ip address of instances in state for env
output "instances" {
    value = module.main.instances
}


module "mix" {
    source             = "../../modules/mix"
    depends_on = [ module.main ]

    server_name_prefix = local.server_name_prefix
    active_env_provider = var.active_env_provider
    region           = var.active_env_provider == "digital_ocean" ? var.do_region : var.aws_region_alias

    # TODO: Map
    vpc_private_iface = var.active_env_provider == "digital_ocean" ? "eth1" : "ens5"
    s3alias = var.active_env_provider == "digital_ocean" ? "spaces" : "s3"
    s3bucket = var.active_env_provider == "digital_ocean" ? var.do_spaces_name : var.aws_bucket_name

    do_spaces_region = var.do_spaces_region
    do_spaces_access_key = var.do_spaces_access_key
    do_spaces_secret_key = var.do_spaces_secret_key

    aws_ecr_region   = var.aws_ecr_region

    servers = var.servers

    # TODO: Cleaner as we introduce Azure and Google Cloud
    admin_private_ips = module.main.admin_private_ip_addresses
    lead_private_ips = module.main.lead_private_ip_addresses
    db_private_ips = module.main.db_private_ip_addresses
    build_private_ips = module.main.build_private_ip_addresses

    admin_public_ips = module.main.admin_public_ip_addresses
    lead_public_ips = module.main.lead_public_ip_addresses
    db_public_ips = module.main.db_public_ip_addresses
    build_public_ips = module.main.build_public_ip_addresses

    admin_names = module.main.admin_names
    lead_names = module.main.lead_names
    db_names = module.main.db_names
    build_names = module.main.build_names

    db_ids = module.main.db_ids

    ansible_hosts = module.main.ansible_hosts
    ansible_hostfile = "./${terraform.workspace}_ansible_hosts"

    mattermost_subdomain = var.mattermost_subdomain
    wekan_subdomain = var.wekan_subdomain

    import_dbs          = var.import_dbs
    install_unity3d     = var.install_unity3d

    dbs_to_import       = var.dbs_to_import
    redis_dbs = local.redis_dbs
    pg_dbs = local.pg_dbs
    mongo_dbs = local.mongo_dbs

    serverkey        = var.serverkey
    pg_password      = var.pg_password
    dev_pg_password  = var.dev_pg_password

    aws_bot_access_key = var.aws_bot_access_key
    aws_bot_secret_key = var.aws_bot_secret_key

    gitlab_backups_enabled = var.gitlab_backups_enabled
    import_gitlab = var.import_gitlab
    import_gitlab_version = var.import_gitlab_version
    gitlab_runner_tokens = var.import_gitlab ? local.gitlab_runner_tokens : {service = ""}
    runners_per_machine = local.runners_per_machine

    app_definitions = var.app_definitions
    misc_repos = var.misc_repos

    contact_email      = var.contact_email

    sendgrid_apikey = local.sendgrid_apikey
    sendgrid_domain = local.sendgrid_domain

    root_domain_name = local.root_domain_name
    additional_domains = terraform.workspace == "default" ? var.additional_domains : {}
    additional_ssl = var.additional_ssl

    use_gpg = var.use_gpg
    bot_gpg_name = var.bot_gpg_name
    bot_gpg_passphrase = var.bot_gpg_passphrase

    kubernetes_version = var.kubernetes_version
    container_orchestrators = var.container_orchestrators

    # TODO: Dynamically change if using multiple providers/modules
    #external_leaderIP = (var.active_env_provider == "digital_ocean"
    #    ? element(concat(module.main.lead_public_ip_addresses, [""]), 0)
    #    : element(concat(module.main.lead_public_ip_addresses, [""]), 0))


    # TODO: Review cross data center communication
    # do_leaderIP
    # aws_leaderIP = "${module.aws.aws_ip}"
}

locals {

    redis_dbs = [
        for db in var.dbs_to_import:
        {name = db.dbname, backups_enabled = db.backups_enabled}
        if db.type == "redis" && ( db.import == "true" || db.backups_enabled == "true" )
    ]
    pg_dbs = [
        for db in var.dbs_to_import:
        {name = db.dbname, backups_enabled = db.backups_enabled}
        if db.type == "pg" && ( db.import == "true" || db.backups_enabled == "true" )
    ]
    mongo_dbs = [
        for db in var.dbs_to_import:
        {name = db.dbname, backups_enabled = db.backups_enabled}
        if db.type == "mongo" && ( db.import == "true" || db.backups_enabled == "true" )
    ]

    config = {
        root_domain_name = local.root_domain_name
        gitlab_subdomain = var.gitlab_subdomain
        additional_domains = terraform.workspace == "default" ? var.additional_domains : {}
        additional_ssl = var.additional_ssl
        server_name_prefix = local.server_name_prefix
        active_env_provider = var.active_env_provider

        region = var.active_env_provider == "digital_ocean" ? var.do_region : var.aws_region_alias

        # TODO: Map
        s3alias = var.active_env_provider == "digital_ocean" ? "spaces" : "s3"
        s3bucket = var.active_env_provider == "digital_ocean" ? var.do_spaces_name : var.aws_bucket_name

        do_token = var.do_token
        do_region = var.do_region
        do_ssh_fingerprint = var.do_ssh_fingerprint
        do_spaces_region = var.do_spaces_region
        do_spaces_access_key = var.do_spaces_access_key
        do_spaces_access_key = var.do_spaces_access_key

        aws_key_name = var.aws_key_name
        aws_access_key = var.aws_access_key
        aws_secret_key = var.aws_secret_key
        aws_region = var.aws_region
        aws_bot_access_key = var.aws_bot_access_key
        aws_bot_secret_key = var.aws_bot_secret_key

        local_ssh_key_file = var.local_ssh_key_file

        servers = var.servers
        downsize = var.downsize

        stun_port = var.stun_port
        docker_machine_ip = var.docker_machine_ip

        admin_arecord_aliases = var.admin_arecord_aliases
        db_arecord_aliases = var.db_arecord_aliases
        leader_arecord_aliases = var.leader_arecord_aliases
        offsite_arecord_aliases = var.offsite_arecord_aliases
        app_definitions = var.app_definitions

        cidr_block = local.cidr_block
        app_ips = var.app_ips
        station_ips = var.station_ips

        packer_config = var.packer_config

        placeholder_reusable_delegationset_id = var.placeholder_reusable_delegationset_id

        misc_cnames = concat([], local.misc_cnames)

        gitlab_backups_enabled = var.gitlab_backups_enabled
        use_gpg = var.use_gpg

        #dbs_to_import       = var.dbs_to_import
        redis_dbs = local.redis_dbs
        pg_dbs = local.pg_dbs
        mongo_dbs = local.mongo_dbs

        known_hosts = var.known_hosts
        deploy_key_location = var.deploy_key_location
        pg_read_only_pw = var.pg_read_only_pw

        nodeexporter_version = var.nodeexporter_version
        promtail_version = var.promtail_version
        consulexporter_version = var.consulexporter_version
        loki_version = var.loki_version
    }
}
