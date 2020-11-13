###################################
####### Variables inside modules not intended to be modified
###################################
#### Only apps.tf, credentials.tf, and vars.tf should be modified
###################################
terraform {
  required_version = ">= 0.12"
}
# terraform {
#     required_providers {
#         aws = {
#             source = "hashicorp/aws"
#         }
#         digitalocean = {
#             source = "digitalocean/digitalocean"
#         }
#     }
#   required_version = ">= 0.13"
# }

# `terraform output` for name and ip address of instances in state for env
output "aws_instances" {
    value = module.aws.instances
}

module "packer" {
    source             = "../../modules/packer"

    active_env_provider = var.active_env_provider
    aws_access_key = var.aws_access_key
    aws_secret_key = var.aws_secret_key
    aws_region = var.aws_region
    aws_key_name = var.aws_key_name

    packer_config = var.packer_config
}

module "digital_ocean" {
    source             = "../../modules/digital_ocean"
    server_name_prefix = var.server_name_prefix
    active_env_provider = var.active_env_provider
    region = var.do_region

    do_ssh_fingerprint = var.do_ssh_fingerprint

    servers = var.servers

    app_ips = var.app_ips
    station_ips = var.station_ips
}

module "aws" {
    source             = "../../modules/aws"
    root_domain_name = var.root_domain_name
    dns_provider = var.dns_provider
    server_name_prefix = var.server_name_prefix
    active_env_provider = var.active_env_provider
    region = var.aws_region_alias

    aws_key_name = var.aws_key_name
    local_ssh_key_file = var.local_ssh_key_file

    servers = var.servers
    downsize = var.downsize

    stun_port = var.stun_port
    docker_machine_ip = var.docker_machine_ip

    admin_arecord_aliases = var.admin_arecord_aliases
    db_arecord_aliases = var.db_arecord_aliases
    leader_arecord_aliases = var.leader_arecord_aliases
    app_definitions = var.app_definitions

    app_ips = var.app_ips
    station_ips = var.station_ips

    packer_image_id = module.packer.image_id
}

module "mix" {
    source             = "../../modules/mix"
    server_name_prefix = var.server_name_prefix
    active_env_provider = var.active_env_provider
    region           = var.active_env_provider == "digital_ocean" ? var.do_region : var.aws_region_alias

    aws_ecr_region   = var.aws_ecr_region
    aws_bucket_region   = var.aws_bucket_region
    aws_bucket_name   = var.aws_bucket_name

    servers = var.servers

    # TODO: Cleaner as we introduce Azure and Google Cloud
    admin_private_ips = compact(concat(module.aws.admin_private_ip_addresses, module.digital_ocean.admin_private_ip_addresses))
    lead_private_ips = compact(concat(module.aws.lead_private_ip_addresses, module.digital_ocean.lead_private_ip_addresses))
    db_private_ips = compact(concat(module.aws.db_private_ip_addresses, module.digital_ocean.db_private_ip_addresses))

    admin_public_ips = compact(concat(module.aws.admin_public_ip_addresses, module.digital_ocean.admin_public_ip_addresses))
    lead_public_ips = compact(concat(module.aws.lead_public_ip_addresses, module.digital_ocean.lead_public_ip_addresses))
    db_public_ips = compact(concat(module.aws.db_public_ip_addresses, module.digital_ocean.db_public_ip_addresses))

    admin_names = compact(concat(module.aws.admin_names, module.digital_ocean.admin_names))
    lead_names = compact(concat(module.aws.lead_names, module.digital_ocean.lead_names))
    db_names = compact(concat(module.aws.db_names, module.digital_ocean.db_names))

    db_ids = compact(concat(module.aws.db_ids, module.digital_ocean.db_ids))

    cloudflare_email    = var.cloudflare_email
    cloudflare_auth_key = var.cloudflare_auth_key
    cloudflare_zone_id  = var.cloudflare_zone_id

    mattermost_subdomain = var.mattermost_subdomain
    wekan_subdomain = var.wekan_subdomain

    db_backups_enabled  = var.db_backups_enabled
    run_service_enabled = var.run_service_enabled
    send_logs_enabled   = var.send_logs_enabled
    send_jsons_enabled  = var.send_jsons_enabled
    import_dbs          = var.import_dbs

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
    gitlab_runner_tokens = var.gitlab_runner_tokens
    num_gitlab_runners = var.num_gitlab_runners

    known_hosts = var.known_hosts
    app_definitions = var.app_definitions
    misc_repos = var.misc_repos

    # Temp
    # docker_engine_install_url  = format("https://raw.githubusercontent.com/rancher/install-docker/master/%s.sh", var.packer_config.docker_version)
    # docker_engine_install_url  = "https://gitlab.codeopensrc.com/os/workbench/-/raw/master/modules/packer/scripts/install/install_docker.sh"

    gitlab_server_url = var.gitlab_server_url
    chef_email      = var.chef_email

    root_domain_name = var.root_domain_name

    external_leaderIP = (var.active_env_provider == "digital_ocean"
        ? element(concat(module.aws.lead_public_ip_addresses, [""]), 0)
        : element(concat(module.digital_ocean.lead_public_ip_addresses, [""]), 0))


    # TODO: Review cross data center communication
    # do_leaderIP
    # aws_leaderIP = "${module.aws.aws_ip}"
}
