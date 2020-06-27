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

# Have new nodes join a swarm with a node that has a specific ID if docker versions match
# It should remain an empty string in version control
variable "join_machine_id" { default = "" }

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

variable "gitlab_version" { default = "13.0.7-ce.0" }

variable "docker_compose_version" { default = "1.19.0" }
variable "docker_engine_install_url" { default = "https://get.docker.com" }

variable "consul_version" { default = "1.0.6" }
variable "redis_version" { default = "5.0.9" }

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

variable "admin" { default = 1 }
variable "leader" { default = 1 }
variable "db" { default = 1 }
variable "web" { default = 0 }
variable "dev" { default = 0 }
variable "build" { default = 0 }
variable "mongo" { default = 0 }
variable "pg" { default = 0 }
variable "redis" { default = 0 }
variable "legacy" { default = 0 }

########## Digital Ocean ##########
variable "do_region" { default = "nyc1" }

variable "do_admin_size" { default = "s-2vcpu-8gb" }
variable "do_leader_size" { default = "s-2vcpu-4gb" }
variable "do_db_size" { default = "s-2vcpu-4gb" }
variable "do_web_size" { default = "1gb" }
variable "do_dev_size" { default = "1gb" }
variable "do_legacy_size" { default = "1gb" }
variable "do_build_size" { default = "s-2vcpu-4gb" }
variable "do_mongo_size" { default = "s-2vcpu-4gb" }
variable "do_pg_size" { default = "s-2vcpu-4gb" }
variable "do_redis_size" { default = "s-2vcpu-4gb" }


########## AWS ##########
variable "aws_region_alias" { default = "awseast" }
variable "build_packer_image" { default = true }
variable "use_packer_image" { default = true }
variable "aws_ami" { default = "" } # NOTE: If `use_packer_image` set to false, MUST provide ami

variable "packer_default_amis" {
    default = {
        "us-east-2" = "ami-0d03add87774b12c5"
    }
}

variable "aws_admin_instance_type" { default = "t2.large" }
variable "aws_leader_instance_type" { default = "t2.medium" }
variable "aws_db_instance_type" { default = "t2.medium" }
variable "aws_web_instance_type" { default = "t2.micro" }
variable "aws_build_instance_type" { default = "t2.micro" }
variable "aws_mongo_instance_type" { default = "t2.micro" }
variable "aws_pg_instance_type" { default = "t2.micro" }
variable "aws_redis_instance_type" { default = "t2.micro" }


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
    default = [ "www" ]
}

variable "misc_repos" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string,
        docker_service_name=string, consul_service_name=string, folder_location=string,
        logs_prefix=string, email_image=string
    }))
    default = {}
}
