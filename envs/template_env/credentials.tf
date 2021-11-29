#NOTE: .pub of this private key file must be in modules/packer/ignore/authorized_keys file. See modules/packer/packer.json
variable "local_ssh_key_file" { default = "~/.ssh/id_rsa" } #Local ssh key file location of aws_key_name and do_ssh_fingerprint

##### Digital Ocean only
variable "do_ssh_fingerprint" { default = "" }
variable "do_token" { default = "" }
## Spaces
variable "do_spaces_name" { default = "" }
variable "do_spaces_region" { default = "" }
variable "do_spaces_access_key" { default = "" }
variable "do_spaces_secret_key" { default = "" }
#####

##### AWS only
variable "aws_key_name" { default = "id_rsa" }
variable "aws_access_key" { default = ""}
variable "aws_secret_key" { default = ""}
## S3
variable "aws_bucket_name" { default = ""}
variable "aws_bot_access_key" { default = "" }
variable "aws_bot_secret_key" { default = "" }
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
    ## If only 1 machine, 4 runners
    default_runners_per_machine = {
        "default" = 2
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

    # Additional configurable cname aliases: subdomainname -> alias
    misc_cnames = lookup(local.misc_cname_aliases, local.env)

    # Gitlab runner registration token
    gitlab_runner_registration_tokens = lookup(local.gitlab_runner_tokens_list, local.env)

    # This is used for the fqdn
    root_domain_name = lookup(local.root_domain_names, local.env)

    # This should be unique per terraform env/workspace in order to not have server names clashing
    server_name_prefix = lookup(local.server_name_prefixes, local.env)

    cidr_block = lookup(local.cidr_blocks, local.env)
    num_runners_per_machine = lookup(local.default_runners_per_machine, local.env, 2)

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
#    backend "s3" {
#        bucket = "bucket_name"
#        key    = "terra_state/template_env"
#        workspace_key_prefix = "terra_state"
#        region = "us-east-2" ##! Must be valid aws region name even if digital ocean backend
#        access_key = "" ##! S3 access key.
#        secret_key = "" ##! S3 secret access key.
#
#        ###! Uncomment below to enable backend using digital ocean Spaces
#        # endpoint = "https://SPACES_REGION.digitaloceanspaces.com"
#        # skip_credentials_validation = true
#        # skip_metadata_api_check = true
#    }
#}

##! NOTE: If using local file for terraform state
data "terraform_remote_state" "cloud" {
    backend = "local"
    workspace = "default"
    config = { path = "./terraform.tfstate" }
}

##! NOTE: If using s3 backend for terraform state
#data "terraform_remote_state" "cloud" {
#    backend = "s3"
#    workspace = terraform.workspace
#    config = {
#        key    = "terra_state/template_env"     ## Should match backend s3 key
#        workspace_key_prefix = "terra_state"    ## Should match backend s3 workspace_key_prefix
#        bucket = local.data_state_bucket[local.active_s3_provider]
#        region = local.data_state_bucketregion[local.active_s3_provider]
#        access_key = local.data_state_s3_access_key[local.active_s3_provider]
#        secret_key = local.data_state_s3_secret_key[local.active_s3_provider]
#
#        ###! Uncomment below to enable backend using digital ocean Spaces
#        #endpoint = local.data_state_remote_endpoint[local.active_s3_provider]
#        #skip_credentials_validation = true
#        #skip_metadata_api_check = true
#    }
#}

locals {
    data_state_s3_access_key = {
        "aws" = var.aws_bot_access_key
        "digital_ocean" = var.do_spaces_access_key
    }
    data_state_s3_secret_key = {
        "aws" = var.aws_bot_secret_key
        "digital_ocean" = var.do_spaces_secret_key
    }
    data_state_bucket = {
        "aws" = var.aws_bucket_name
        "digital_ocean" = var.do_spaces_name
    }
    ##! Must be valid aws region name even if digital ocean backend - so we use us-east-2 placeholder
    data_state_bucketregion = {
        "aws" = var.aws_region
        "digital_ocean" = "us-east-2"
    }
    data_state_remote_endpoint = {
        #"aws" = ""  ## s3 backend endpoint for aws shouldnt be needed
        "digital_ocean" = "https://${var.do_region}.digitaloceanspaces.com"
    }
}
