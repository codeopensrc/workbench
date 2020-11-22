variable "do_ssh_fingerprint" { default = "" }

### Template
variable "do_token" { default = "" }

### Template
variable "aws_key_name" { default = "id_rsa" }
variable "local_ssh_key_file" { default = "~/.ssh/id_rsa" } #Local ssh key file location of aws_key_name
#NOTE: .pub of this private key file must be in modules/packer/ignore/authorized_keys file. See modules/packer/packer.json

# TODO: Configure multiple bucket name access (dev/stage. db/static/images etc)
variable "aws_bucket_name" { default = ""}
variable "aws_bucket_region" { default = ""}

variable "aws_access_key" { default = ""}
variable "aws_secret_key" { default = ""}
variable "aws_bot_access_key" { default = "" }
variable "aws_bot_secret_key" { default = "" }

variable "pg_password" { default = "" }
variable "pg_read_only_pw" { default = "" }
variable "dev_pg_password" { default = "" }

# When making security groups, allow all port access to 1 ip of terraform user (until we revisit this)
# This is the workstation ip that will connect to this cluster
variable "docker_machine_ip" { default = "" }

# Random uuid to pass to and initially populate for possible communication
#   from a server/app/serivce to another
# TBH not sure its used anymore
variable "serverkey" { default = ""}

# TODO: Change to contact email and an admin-like subdomain
variable "chef_email" { default = "your@email.com" }
variable "gitlab_server_url" { default = "gitlab.DOMAIN.COM" }

# This is used for the fqdn
variable "root_domain_name" { default = "DOMAIN.COM" }

# This should be unique per terraform machine/env in order to not have server names clashing
# Replace USER with your name and ENV with [prod, dev, test, stage, w/e]
variable "server_name_prefix" { default = "NAME-blue" }

variable "gitlab_runner_tokens" {
    type = map(string)
    default = {
        service = "token_value"
    }
}

###! To use s3 backend for remote state, backup any current .tfstate file.
###! Adjust and uncomment below
###! After re-running `terrafom init` all contents of .tfstate will move to and be stored in s3 after reinitialization
###! To create a local `terraform.tfstate` backup of the remote version: `terraform state pull > terraform.tfstate`
###! Values cannot be interpolated in the configuration below
###! https://www.terraform.io/docs/backends/config.html#first-time-configuration
# terraform {
#     backend "s3" {
#         bucket = "aws_bucket_name"
#         key    = "remote_states/template_env"
#         region = "aws_bucket_region"
#         access_key = "aws_access_key" ## (Optional)
#         secret_key = "aws_secret_key" ## (Optional)
#     }
# }
