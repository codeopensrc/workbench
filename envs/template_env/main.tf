###################################
####### Variables inside modules not intended to be modified
###################################
#### Only apps.tf, credentials.tf, and vars.tf should be modified
###################################
terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
        }
        digitalocean = {
            source = "digitalocean/digitalocean"
        }
    }
    required_version = ">= 0.13"
}

# `terraform output` for name and ip address of instances in state for env
output "aws_instances" {
    value = var.active_env_provider == "aws" ? tolist(module.aws)[0].instances : {}
}

output "digital_ocean_instances" {
    value = var.active_env_provider == "digital_ocean" ? tolist(module.digital_ocean)[0].instances : {}
}

module "packer" {
    source             = "../../modules/packer"

    active_env_provider = var.active_env_provider

    aws_access_key = var.aws_access_key
    aws_secret_key = var.aws_secret_key
    aws_region = var.aws_region
    aws_key_name = var.aws_key_name
    aws_instance_type = "t2.medium"

    do_token = var.do_token
    digitalocean_region = var.do_region
    digitalocean_image_size = "s-2vcpu-4gb"

    packer_config = var.packer_config
}

module "digital_ocean" {
    count = var.active_env_provider == "digital_ocean" ? 1 : 0
    source             = "../../modules/digital_ocean"
    root_domain_name = var.root_domain_name
    dns_provider = var.dns_provider
    server_name_prefix = var.server_name_prefix
    active_env_provider = var.active_env_provider
    region = var.do_region

    do_ssh_fingerprint = var.do_ssh_fingerprint
    local_ssh_key_file = var.local_ssh_key_file

    digitalocean_image_os = var.packer_config.digitalocean_image_os["main"]

    servers = var.servers
    downsize = var.downsize

    stun_port = var.stun_port
    docker_machine_ip = var.docker_machine_ip

    admin_arecord_aliases = var.admin_arecord_aliases
    db_arecord_aliases = var.db_arecord_aliases
    leader_arecord_aliases = var.leader_arecord_aliases
    app_definitions = var.app_definitions

    cidr_block = var.cidr_block
    app_ips = var.app_ips
    station_ips = var.station_ips

    packer_image_id = module.packer.image_id
}

module "aws" {
    count = var.active_env_provider == "aws" ? 1 : 0
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

    cidr_block = var.cidr_block
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
    admin_private_ips = compact(concat(local.aws_admin_private_ips, local.digital_ocean_admin_private_ips))
    lead_private_ips = compact(concat(local.aws_lead_private_ips, local.digital_ocean_lead_private_ips))
    db_private_ips = compact(concat(local.aws_db_private_ips, local.digital_ocean_db_private_ips))

    admin_public_ips = compact(concat(local.aws_admin_public_ips, local.digital_ocean_admin_public_ips))
    lead_public_ips = compact(concat(local.aws_lead_public_ips, local.digital_ocean_lead_public_ips))
    db_public_ips = compact(concat(local.aws_db_public_ips, local.digital_ocean_db_public_ips))

    admin_names = compact(concat(local.aws_admin_names, local.digital_ocean_admin_names))
    lead_names = compact(concat(local.aws_lead_names, local.digital_ocean_lead_names))
    db_names = compact(concat(local.aws_db_names, local.digital_ocean_db_names))

    db_ids = compact(concat(local.aws_db_ids, local.digital_ocean_db_ids))


    mattermost_subdomain = var.mattermost_subdomain
    wekan_subdomain = var.wekan_subdomain

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
    import_gitlab_version = var.import_gitlab_version
    gitlab_runner_tokens = var.gitlab_runner_tokens
    num_gitlab_runners = var.num_gitlab_runners

    known_hosts = var.known_hosts
    app_definitions = var.app_definitions
    misc_repos = var.misc_repos

    gitlab_subdomain = var.gitlab_subdomain
    contact_email      = var.contact_email

    root_domain_name = var.root_domain_name

    external_leaderIP = (var.active_env_provider == "digital_ocean"
        ? element(concat(local.aws_lead_public_ips, [""]), 0)
        : element(concat(local.digital_ocean_lead_public_ips, [""]), 0))


    # TODO: Review cross data center communication
    # do_leaderIP
    # aws_leaderIP = "${module.aws.aws_ip}"
}

locals {

    aws_admin_private_ips = var.active_env_provider == "aws" ? tolist(module.aws)[0].admin_private_ip_addresses : []
    aws_lead_private_ips = var.active_env_provider == "aws" ? tolist(module.aws)[0].lead_private_ip_addresses : []
    aws_db_private_ips = var.active_env_provider == "aws" ? tolist(module.aws)[0].db_private_ip_addresses : []

    aws_admin_public_ips = var.active_env_provider == "aws" ? tolist(module.aws)[0].admin_public_ip_addresses : []
    aws_lead_public_ips = var.active_env_provider == "aws" ? tolist(module.aws)[0].lead_public_ip_addresses : []
    aws_db_public_ips = var.active_env_provider == "aws" ? tolist(module.aws)[0].db_public_ip_addresses : []

    aws_admin_names = var.active_env_provider == "aws" ? tolist(module.aws)[0].admin_names : []
    aws_lead_names = var.active_env_provider == "aws" ? tolist(module.aws)[0].lead_names : []
    aws_db_names = var.active_env_provider == "aws" ? tolist(module.aws)[0].db_names : []

    aws_db_ids = var.active_env_provider == "aws" ? tolist(module.aws)[0].db_ids : []

    digital_ocean_admin_private_ips = var.active_env_provider == "digital_ocean" ? tolist(module.digital_ocean)[0].admin_private_ip_addresses : []
    digital_ocean_lead_private_ips = var.active_env_provider == "digital_ocean" ? tolist(module.digital_ocean)[0].lead_private_ip_addresses : []
    digital_ocean_db_private_ips = var.active_env_provider == "digital_ocean" ? tolist(module.digital_ocean)[0].db_private_ip_addresses : []

    digital_ocean_admin_public_ips = var.active_env_provider == "digital_ocean" ? tolist(module.digital_ocean)[0].admin_public_ip_addresses : []
    digital_ocean_lead_public_ips = var.active_env_provider == "digital_ocean" ? tolist(module.digital_ocean)[0].lead_public_ip_addresses : []
    digital_ocean_db_public_ips = var.active_env_provider == "digital_ocean" ? tolist(module.digital_ocean)[0].db_public_ip_addresses : []

    digital_ocean_admin_names = var.active_env_provider == "digital_ocean" ? tolist(module.digital_ocean)[0].admin_names : []
    digital_ocean_lead_names = var.active_env_provider == "digital_ocean" ? tolist(module.digital_ocean)[0].lead_names : []
    digital_ocean_db_names = var.active_env_provider == "digital_ocean" ? tolist(module.digital_ocean)[0].db_names : []

    digital_ocean_db_ids = var.active_env_provider == "digital_ocean" ? tolist(module.digital_ocean)[0].db_ids : []
}
