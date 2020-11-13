########## PROVIDER CREDENTIALS ##########
##########################################
provider "digitalocean" {
    token = var.do_token
}

variable "aws_region" { default = "us-east-2" }
variable "aws_ecr_region" { default = "us-east-2" }
provider "aws" {
    region = var.aws_region

    # profile = "${var.profile}"
    access_key = var.aws_access_key
    secret_key = var.aws_secret_key
}

########## MISC CONFIG/VARIABLES ##########
############################################
variable "stun_port" { default = "" }

variable "import_gitlab" { default = false }
variable "num_gitlab_runners" { default = 0 }

variable "gitlab_backups_enabled" { default = false }
variable "run_service_enabled" { default = false }
variable "send_logs_enabled" { default = false }
variable "send_jsons_enabled" { default = false }
variable "db_backups_enabled" { default = false }

variable "dns_provider" { default = "aws_route53" }

########## SOFTWARE VERSIONS ##########
#######################################
variable "packer_config" {
    default = {
        gitlab_version = "13.0.6-ce.0"
        docker_version = "19.03.12"
        docker_compose_version = "1.19.0"
        consul_version = "1.0.6"
        redis_version = "5.0.9"
        base_amis = {
            "us-east-2" = "ami-0d03add87774b12c5"
        }
    }
}

########## CLOUD MACHINES ##########
####################################

# TODO: Azure and Google Cloud providers
# Options will be digital_ocean, aws, azure, google_cloud etc.

#### DISCLAIMER: THIS DOES NOT CREATE A FIREWALL ON DIGITAL OCEAN AT THIS TIME
#### Switched AWS module over to aws_security groups while a digital ocean/UFW implementation has
####   not yet been re-implemented
#### Also does not have a packer builder to build a digital ocean image at this time (simple just not done atm).
#### For now this now only supports "aws" until a builder created for digital ocean in a_root/mix/modules/packer/packer.json
variable "active_env_provider" { default = "aws" }

# Currently supports 1 server with all 3 roles or 3 servers each with a single role
# Supports admin+lead+db and 1 server as lead as well
# Believe it also supports 1 server as admin+lead and 1 server as db but untested
# NOTE: Count attribute currently only supports 1 until we can scale more dynamically

###! When downsizing from 2 to 1 leader, set downsize = true, terraform apply. This adjusts app routing.
###! Then comment/remove 2nd server, downsize = false, and terraform apply again to remove it
variable "downsize" { default = false }

variable "servers" {
    ### NOTE: Do not add or remove roles from instances after they are launched for now
    ###  as each instance's roles are tagged at boot and updating tags will cause unpredictable issues at this time
    default = [
        {
            "count" = 1
            "roles" = ["admin", "lead", "db"]
            # "roles" = ["admin"]
            "size" = "t3a.large"   ### "t3a.small"   "t3a.micro"
            "aws_volume_size" = 50
            "region" = "us-east-2"
            "provider" = "aws"
            "image" = ""
        },
        # {
        #     "count" = 1
        #     "roles" = ["lead"]
        #     "size" = "t3a.small"
        #     "aws_volume_size" = 50
        #     "region" = "us-east-2"
        #     "provider" = "aws"
        #     "image" = ""
        # },
        # {
        #     "count" = 1
        #     "roles" = ["db"]
        #     "size" = "t3a.micro"
        #     "aws_volume_size" = 50
        #     "region" = "us-east-2"
        #     "provider" = "aws"
        #     "image" = ""
        # },
    ]
}

########## Digital Ocean ##########
variable "do_region" { default = "nyc1" }


########## AWS ##########
variable "aws_region_alias" { default = "awseast" }


############ DNS ############
#############################
# Used for gitlab oauth plugins
variable "mattermost_subdomain" { default = "" }
variable "wekan_subdomain" { default = "" }

# A record
variable "admin_arecord_aliases" {
    default = [
        "cert",
        "chef",
        "consul",
        "gitlab",
        "registry",
    ]
    # Add mattermost_subdomain to this list
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
