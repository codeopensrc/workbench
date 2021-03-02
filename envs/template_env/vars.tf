########## Digital Ocean ##########
variable "do_region" { default = "nyc3" }

########## AWS ##########
variable "aws_region_alias" { default = "awseast" }
variable "aws_region" { default = "us-east-2" }
variable "aws_ecr_region" { default = "us-east-2" }

########## PROVIDER CREDENTIALS ##########
##########################################
provider "digitalocean" {
    token = var.do_token
}

provider "aws" {
    region = var.aws_region

    # profile = "${var.profile}"
    access_key = var.aws_access_key
    secret_key = var.aws_secret_key
}

########## MISC CONFIG/VARIABLES ##########
############################################
variable "stun_port" { default = "" }
variable "cidr_block" { default = "10.1.0.0/16" }

variable "import_gitlab" { default = false }
variable "import_gitlab_version" { default = "" }
variable "num_gitlab_runners" { default = 0 }

variable "gitlab_backups_enabled" { default = false }
variable "run_service_enabled" { default = false }
variable "send_logs_enabled" { default = false }
variable "send_jsons_enabled" { default = false }

########## SOFTWARE VERSIONS ##########
#######################################
variable "packer_config" {
    default = {
        gitlab_version = "13.5.4-ce.0"
        docker_version = "19.03.12"
        docker_compose_version = "1.27.4"
        consul_version = "1.0.6"
        redis_version = "5.0.9"
        base_amis = {
            "us-east-2" = "ami-0d03add87774b12c5"
        }
        digitalocean_image_os = {
            "main" = "ubuntu-16-04-x64"
        }
    }
}

########## CLOUD MACHINES ##########
####################################

# TODO: Azure and Google Cloud providers
# Options will be digital_ocean, aws, azure, google_cloud etc.
variable "active_env_provider" { default = "digital_ocean" } # "digital_ocean" or "aws"

# Currently supports 1 server with all 3 roles or 3 servers each with a single role
# Supports admin+lead+db and 1 server as lead as well
# Believe it also supports 1 server as admin+lead and 1 server as db but untested
# NOTE: Count attribute currently only supports 1 until we can scale more dynamically

###! When downsizing from 2 to 1 leader, set downsize = true, terraform apply. This adjusts app routing.
###! Then comment/remove 2nd server, downsize = false, and terraform apply again to remove it
variable "downsize" { default = false }

variable "servers" {
    ### NOTE: Do not add or remove roles from instances after they are launched
    default = [
        {
            "count" = 1
            "image" = ""
            "roles" = ["admin", "lead", "db"]
            # "roles" = ["admin"]
            "size" = {
                "aws" = ["t3a.micro", "t3a.small", "t3a.medium", "t3.large"][3]
                "digital_ocean" = ["s-2vcpu-4gb", "s-4vcpu-8gb"][1]
            }
            "aws_volume_size" = 60
        },
        # {
        #     "count" = 1
        #     "image" = ""
        #     "roles" = ["lead"]
        #     "size" = {
        #         "aws" = ["t3a.micro", "t3a.small", "t3a.medium", "t3.large"][1]
        #         "digital_ocean" = ["s-2vcpu-4gb", "s-4vcpu-8gb"][0]
        #     }
        #     "aws_volume_size" = 40
        # },
        # {
        #     "count" = 1
        #     "image" = ""
        #     "roles" = ["db"]
        #     "size" = {
        #         "aws" = ["t3a.micro", "t3a.small", "t3a.medium", "t3.large"][1]
        #         "digital_ocean" = ["s-2vcpu-4gb", "s-4vcpu-8gb"][0]
        #     }
        #     "aws_volume_size" = 40
        # },
    ]
}

############ DNS ############
#############################
variable "gitlab_subdomain" { default = "gitlab" }
# Used for gitlab oauth plugins
variable "mattermost_subdomain" { default = "chat" }
variable "wekan_subdomain" { default = "wekan" }

# A record
variable "admin_arecord_aliases" {
    default = [
        "cert",
        "consul",
        "gitlab",
        "registry",
        "chat",
        "btcpay"
    ]
}

variable "db_arecord_aliases" {
    default = [
        "mongo.aws1",
        "mongo.do1",
        "pg.aws1",
        "pg.do1",
        "redis.aws1",
        "redis.do1",
    ]
}

variable "leader_arecord_aliases" {
    default = [ ]
}

variable "misc_repos" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string, docker_registry_image=string,
        docker_service_name=string, consul_service_name=string, folder_location=string,
        logs_prefix=string, email_image=string
    }))
    default = {}
}
