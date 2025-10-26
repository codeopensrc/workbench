#NOTE: .pub of this private key file must be in modules/packer/ignore/authorized_keys file. See modules/packer/packer.json
variable "local_ssh_key_file" { default = "~/.ssh/id_rsa" } #Local ssh key file location of aws_key_name and do_ssh_fingerprint

##### Digital Ocean only
variable "do_ssh_fingerprint" { default = "" }
variable "do_token" { default = "" }
## Spaces (Blob storage)
variable "do_spaces_name" { default = "" }
variable "do_spaces_region" { default = "" }
variable "do_spaces_access_key" { default = "" }
variable "do_spaces_secret_key" { default = "" }
#####

##### AWS only
variable "aws_key_name" { default = "id_rsa" }
variable "aws_access_key" { default = ""}
variable "aws_secret_key" { default = ""}
## AWS S3  (Blob storage)
variable "aws_bucket_name" { default = ""}
variable "aws_bot_access_key" { default = "" }
variable "aws_bot_secret_key" { default = "" }
#####

##### Microsoft Azure only
variable "az_admin_username" { default = ""} ## `ssh-keygen -l -f var.local_ssh_key_file` for name
variable "az_subscriptionId" { default = ""}
variable "az_tenant" { default = ""}
variable "az_appId" { default = "" }
variable "az_password" { default = ""}
### Azure Blob Storage
variable "az_storageaccount" { default = ""} ## storage_account name
variable "az_storagekey" { default = ""}     ## access_key for az_storageaccount
variable "az_bucket_name" { default = "bucket"}
#####


variable "pg_password" { default = "" }
variable "pg_read_only_pw" { default = "" }
variable "dev_pg_password" { default = "" }

# Allow all port access to this workstation ip for this cluster
variable "docker_machine_ip" { default = "" }

variable "contact_email" { default = "your@email.com" }

variable "use_gpg" { default = false }
variable "bot_gpg_name" { default = "" }
variable "bot_gpg_passphrase" {
    default = ""
    sensitive = true
}


locals {
    env = terraform.workspace

    root_domain_names = {
        "default" = "CHANGEME.COM"
    }
    server_name_prefixes = {
        "default" = "pre"
    }
    cidr_blocks = {
        "default" = "10.1.0.0/16"
    }
    s3_backup_buckets = {
        "default" = "UNIQUE-PREFIX-backups"
    }
    env_bucket_prefixes = {
        "default" = "UNIQUE-PREFIX"
    }
    ## TODO: Unity builder inside pods
    ## This is for shell runners on build machines only
    default_runners_per_machine = {
        "default" = 1
    }
    gitlab_runner_tokens_list = {
        "default" = { service = "" }
    }
    misc_cname_aliases = {
        "default" = [
            {
                subdomainname = ""
                alias = ""
            }
        ]
    }
    sendgrid_apikeys = {
        "default" = ""
    }
    sendgrid_domains = {
        "default" = ""
    }

    s3_backup_bucket = lookup(local.s3_backup_buckets, local.env, local.s3_backup_buckets["default"])
    env_bucket_prefix = lookup(local.env_bucket_prefixes, local.env, local.env_bucket_prefixes["default"])

    # Additional configurable cname aliases: subdomainname -> alias
    misc_cnames = lookup(local.misc_cname_aliases, local.env)

    # Gitlab runner registration token
    gitlab_runner_registration_tokens = lookup(local.gitlab_runner_tokens_list, local.env)

    # This is used for the fqdn
    root_domain_name = lookup(local.root_domain_names, local.env)

    # This should be unique per terraform env/workspace in order to not have server names clashing
    server_name_prefix = lookup(local.server_name_prefixes, local.env)

    cidr_block = lookup(local.cidr_blocks, local.env)
    num_runners_per_machine = lookup(local.default_runners_per_machine, local.env, 1)

    # Configures sendgrid SMTP for gitlab using verified domain sender identity
    # TODO: Maybe put in wiki some links to setup and get apikey from sendgrid
    sendgrid_apikey = lookup(local.sendgrid_apikeys, local.env)
    sendgrid_domain = lookup(local.sendgrid_domains, local.env)
}

###! To use s3 backend for remote state, backup any current .tfstate file.
###! Adjust and uncomment below
###! After re-running `terrafom init` all contents of .tfstate will move to and be stored in s3 after reinitialization
###! To create a local `terraform.tfstate` backup of the remote version: `terraform state pull > terraform.tfstate`
###! Values cannot be interpolated in the configuration below
###! https://www.terraform.io/docs/backends/config.html#first-time-configuration

#terraform {
#    ###! Use AWS S3/Digital Ocean Spaces for remote backend
#    backend "s3" {
#        bucket = "bucket_name"
#        key    = "terra_state/template_env"
#        workspace_key_prefix = "terra_state"
#        region = "us-east-2" ##! Must be valid aws region name even if digital ocean backend
#        access_key = "" ##! S3 access key.
#        secret_key = "" ##! S3 secret access key.
#
#        ###! Uncomment below to enable backend using digital ocean Spaces
#        #endpoints = {
#        #    s3 = "https://SPACES_REGION.digitaloceanspaces.com"
#        #}
#        #skip_credentials_validation = true
#        #skip_metadata_api_check = true
#        #skip_requesting_account_id  = true
#        #skip_region_validation      = true
#        #skip_s3_checksum            = true
#    }
#    ###! Use Azure Blob Storage for remote backend instead of s3
#    #backend "azurerm" {
#    #    storage_account_name = ""  ##! az_storageaccount
#    #    access_key = ""            ##! az_storagekey
#    #    container_name       = "bucket" ##! az_bucket_name
#    #    key                  = "terra_state/terraform.tfstate"
#    #}
#}

data "terraform_remote_state" "cloud" {
    ##! NOTE: If using local file for terraform state
    backend = "local"
    workspace = "default"
    config = { path = "./terraform.tfstate" }

    ##! NOTE: If using s3 backend for terraform state
    #backend = "s3"
    #workspace = terraform.workspace
    #config = {
    #    key    = "terra_state/template_env"     ## Should match backend s3 key
    #    workspace_key_prefix = "terra_state"    ## Should match backend s3 workspace_key_prefix
    #    bucket = local.data_state_bucket[local.active_s3_provider]
    #    region = local.data_state_bucketregion[local.active_s3_provider]
    #    access_key = local.data_state_s3_access_key[local.active_s3_provider]
    #    secret_key = local.data_state_s3_secret_key[local.active_s3_provider]

    #    ###! Uncomment below to enable backend using digital ocean Spaces
    #    #endpoints = {
    #    #    s3 = local.data_state_remote_endpoint[local.active_s3_provider]
    #    #}
    #    #skip_credentials_validation = true
    #    #skip_metadata_api_check = true
    #    #skip_requesting_account_id  = true
    #    #skip_region_validation      = true
    #    #skip_s3_checksum            = true
    #}

    ##! NOTE: If using azure backend for terraform state
    #backend = "azurerm"
    #workspace = terraform.workspace
    #config = {
    #    storage_account_name = local.data_state_s3_access_key[local.active_s3_provider]
    #    container_name       = local.data_state_bucket[local.active_s3_provider]
    #    key                  = "terra_state/terraform.tfstate"
    #    access_key = local.data_state_s3_secret_key[local.active_s3_provider]
    #}
}

locals {
    data_state_s3_access_key = {
        "aws" = var.aws_bot_access_key
        "digital_ocean" = var.do_spaces_access_key
        "azure" = var.az_storageaccount
    }
    data_state_s3_secret_key = {
        "aws" = var.aws_bot_secret_key
        "digital_ocean" = var.do_spaces_secret_key
        "azure" = var.az_storagekey
    }
    data_state_bucket = {
        "aws" = var.aws_bucket_name
        "digital_ocean" = var.do_spaces_name
        "azure" = var.az_bucket_name
    }
    ##! Must be valid aws region name even if digital ocean backend - so we use us-east-2 placeholder
    data_state_bucketregion = {
        "aws" = var.aws_region
        "digital_ocean" = "us-east-2"
        "azure" = var.az_region
    }
    data_state_remote_endpoint = {
        "aws" = ""  ## s3 backend endpoint for aws shouldnt be needed
        "digital_ocean" = "https://${var.do_region}.digitaloceanspaces.com"
        "azure" = "" ## azurerm endpoint shouldnt be needed "http://${var.az_storageaccount}.blob.core.windows.net"
    }
}
