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
    server_name_prefix = local.server_name_prefix
    active_env_provider = var.active_env_provider
    region           = var.active_env_provider == "digital_ocean" ? var.do_region : var.aws_region_alias

    # TODO: Map
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


    mattermost_subdomain = var.mattermost_subdomain
    wekan_subdomain = var.wekan_subdomain

    run_service_enabled = var.run_service_enabled
    send_logs_enabled   = var.send_logs_enabled
    send_jsons_enabled  = var.send_jsons_enabled
    import_dbs          = var.import_dbs
    install_unity3d     = var.install_unity3d

    dbs_to_import       = var.dbs_to_import

    serverkey        = var.serverkey
    pg_password      = var.pg_password
    dev_pg_password  = var.dev_pg_password

    aws_bot_access_key = var.aws_bot_access_key
    aws_bot_secret_key = var.aws_bot_secret_key
    pg_read_only_pw = var.pg_read_only_pw

    deploy_key_location = var.deploy_key_location

    gitlab_backups_enabled = var.gitlab_backups_enabled
    import_gitlab = var.import_gitlab
    import_gitlab_version = var.import_gitlab_version
    gitlab_runner_tokens = var.import_gitlab ? local.gitlab_runner_tokens : {service = ""}
    num_gitlab_runners = local.num_gitlab_runners

    known_hosts = var.known_hosts
    app_definitions = var.app_definitions
    misc_repos = var.misc_repos

    gitlab_subdomain = var.gitlab_subdomain
    contact_email      = var.contact_email

    sendgrid_apikey = local.sendgrid_apikey
    sendgrid_domain = local.sendgrid_domain

    root_domain_name = local.root_domain_name
    additional_domains = terraform.workspace == "default" ? var.additional_domains : {}
    additional_ssl = var.additional_ssl

    # TODO: Dynamically change if using multiple providers/modules
    #external_leaderIP = (var.active_env_provider == "digital_ocean"
    #    ? element(concat(module.main.lead_public_ip_addresses, [""]), 0)
    #    : element(concat(module.main.lead_public_ip_addresses, [""]), 0))


    # TODO: Review cross data center communication
    # do_leaderIP
    # aws_leaderIP = "${module.aws.aws_ip}"
}

locals {
    config = {
        root_domain_name = local.root_domain_name
        additional_domains = terraform.workspace == "default" ? var.additional_domains : {}
        additional_ssl = var.additional_ssl
        server_name_prefix = local.server_name_prefix
        active_env_provider = var.active_env_provider

        region = var.active_env_provider == "digital_ocean" ? var.do_region : var.aws_region_alias

        do_token = var.do_token
        do_region = var.do_region
        do_ssh_fingerprint = var.do_ssh_fingerprint

        aws_key_name = var.aws_key_name
        aws_access_key = var.aws_access_key
        aws_secret_key = var.aws_secret_key
        aws_region = var.aws_region

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

        placeholder_hostzone = var.placeholder_hostzone
        placeholder_reusable_delegationset_id = var.placeholder_reusable_delegationset_id

        misc_cnames = concat([], local.misc_cnames)
    }
}
