variable "do_ssh_fingerprint" { default = "" }

### Template
variable "do_token" { default = "" }

### Template
variable "aws_key_name" { default = "id_rsa" }

# TODO: Configure multiple bucket name access (dev/stage. db/static/images etc)
variable "aws_bucket_name" { default = ""}
variable "aws_bucket_region" { default = ""}

variable "aws_access_key" { default = ""}
variable "aws_secret_key" { default = ""}
variable "aws_bot_access_key" { default = "" }
variable "aws_bot_secret_key" { default = "" }

variable "pg_password" { default = "" }
variable "pg_md5_password" { default = "" }
variable "pg_read_only_pw" { default = "" }
variable "dev_pg_password" { default = "" }

variable "cloudflare_email" { default = "" }
variable "cloudflare_auth_key" { default = "" }
variable "cloudflare_zone_id" { default = "" }

# When making security groups, allow all port access to 1 ip of terraform user (until we revisit this)
# This is the workstation ip that will connect to this cluster
variable "docker_machine_ip" { default = "" }

# Random uuid to pass to and initially populate for possible communication
#   from a server/app/serivce to another
# TBH not sure its used anymore
variable "serverkey" { default = ""}

variable "chef_fn" { default = "admin" }
variable "chef_ln" { default = "admin" }
variable "chef_email" { default = "your@email.com" }
variable "chef_user" { default = "admin" }
# NOTE: password must be at least 6 characters...
variable "chef_pw" { default = "adminchangeme123" }

variable "chef_org_short" { default = "" }
variable "chef_org_full" { default = "" }
variable "chef_org_user" { default = "admin" }
variable "chef_server_url" { default = "chef.DOMAIN.COM" }

# This is used to change the fqdn of the leader servers
# It allows a "proxy.erb" template file in chef to be unique per domain
# Upd: Its used in consul to add domainname to consul kv store to be used when needed
#  as every server/container has access to consul
variable "root_domain_name" { default = "DOMAIN.COM" }

variable "gitlab_runner_tokens" {
    type = map(string)
    default = {
        service = "token_value"
    }
}
