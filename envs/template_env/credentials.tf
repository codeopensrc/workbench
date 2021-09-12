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

# Random uuid in consul to use from a server/app/serivce to another for cluster communication
variable "serverkey" { default = ""}

variable "contact_email" { default = "your@email.com" }



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
    default_gitlab_runners = {
        "default" = 2
    }
    gitlab_runner_tokens_list = {
        "default" = { service = "" }
    }

    # Gitlab runner registration token
    gitlab_runner_tokens = lookup(local.gitlab_runner_tokens_list, local.env)

    # This is used for the fqdn
    root_domain_name = lookup(local.root_domain_names, local.env)

    # This should be unique per terraform env/workspace in order to not have server names clashing
    server_name_prefix = lookup(local.server_name_prefixes, local.env)

    cidr_block = lookup(local.cidr_blocks, local.env)
    num_gitlab_runners = lookup(local.default_gitlab_runners, local.env, 2)
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
