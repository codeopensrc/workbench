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

# This should be unique per terraform machine/env in order to not have server names clashing
# Replace USER with your name and ENV with [prod, dev, test, stage, w/e]
variable "server_name_prefix" { default = "NAME-blue" }

# Have new nodes join a swarm with a node that has a specific ID if docker versions match
# It should remain an empty string in version control
variable "join_machine_id" { default = "" }

variable "backup_gitlab" { default = false }
variable "import_gitlab" { default = false }
variable "num_gitlab_runners" { default = 0 }

variable "run_service_enabled" { default = false }
variable "send_logs_enabled" { default = false }
variable "send_jsons_enabled" { default = false }
variable "db_backups_enabled" { default = false }

variable "dns_provider" { default = "aws_route53" }

########## SOFTWARE VERSIONS ##########
#######################################

variable "gitlab_version" { default = "12.10.1-ce.0" }

variable "docker_compose_version" { default = "1.19.0" }
variable "docker_engine_install_url" { default = "https://get.docker.com" }

variable "consul_version" { default = "1.0.6" }

variable "chef_server_ver" { default = "12.19.31" }
variable "chef_dk_ver" { default = "3.8.14" }
variable "chef_client_ver" { default = "14.11.21" }

########## CLOUD MACHINES ##########
####################################

# TODO: Azure and Google Cloud providers
# Options will be digital_ocean, aws, azure, google_cloud
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
variable "aws_ami" { default = "" } #Ohio -us-east-2

variable "aws_admin_instance_type" { default = "t2.large" }
variable "aws_leader_instance_type" { default = "t2.medium" }
variable "aws_db_instance_type" { default = "t2.medium" }
variable "aws_web_instance_type" { default = "t2.micro" }
variable "aws_build_instance_type" { default = "t2.micro" }
variable "aws_mongo_instance_type" { default = "t2.micro" }
variable "aws_pg_instance_type" { default = "t2.micro" }
variable "aws_redis_instance_type" { default = "t2.micro" }


########## CHEF ##########
##########################
# These are necessary for the chef installation on the admin_server

# chef_local_dir is where the credentials for `knife` command are stored
# This ensures the knife command is unique per terraform env, this way
#   the knife command run in say 'prod' doesn't affect the nodes in the 'dev' env
variable "chef_local_dir" { default = "./.chef" }
variable "chef_remote_dir" { default = "/root/.chef" }
variable "chef_server_http_port" { default = "8888" }
variable "chef_server_https_port" { default = "4433" }


############ DNS ############
#############################

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
    default = [
        "www"
    ]
}


############## DB ###########
#############################

variable "import_dbs" { default = true }

variable "dbs_to_import" {
    type = list(object({ type=string, aws_bucket=string, aws_region=string,
        dbname=string, import=string, fn=string }))  # TODO: "fn" hack
    default = [
        {
            "type" = ""
            "aws_bucket" = ""
            "aws_region" = ""
            "dbname" = ""
            "import" = ""
            "fn" = ""
        },
    ]
}


########## APPS ##########
########################

# Location for the private key to upload to the remote server
# This should be a unique ssh key only used to read private repositories using
#  either githubs deploy keys or bitbuckets access keys or gitlabs deploy keys/token
# Each private repo needs the public key already added
variable "deploy_key_location" { default = "~/.ssh/repo_read" }

# TODO: Digital Ocean, Azure, and Google Cloud docker registry options
# Initial Options: docker_hub, aws_ecr
# Aditional Options will be: digital_ocean_registry, azure, google_cloud

variable "app_definitions" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string, docker_registry=string, docker_registry_image=string,
        docker_registry_url=string, docker_registry_user=string, docker_registry_pw=string, service_name=string,
        green_service=string, blue_service=string, default_active=string, create_subdomain=string }))

    default = {
        proxy = {
            "pull"                  = "true"
            "stable_version"        = "0.10.7"
            "use_stable"            = "false"
            "repo_url"              = "https://github.com/Cjones90/os.docker.proxy.git"
            "repo_name"             = "os.docker.proxy"
            "docker_registry"       = "docker_hub"
            "docker_registry_image" = "jestrr/proxy"
            "docker_registry_url"   = ""
            "docker_registry_user"  = ""
            "docker_registry_pw"    = ""
            "service_name"          = "proxy"
            "green_service"         = "proxy_main"
            "blue_service"          = "proxy_dev"
            "default_active"        = "green"
            "create_subdomain"      = "false"
        }
        monitor = {
            "pull"                  = "true"
            "stable_version"        = "0.16.6"
            "use_stable"            = "false"
            "repo_url"              = "https://github.com/Cjones90/os.infra.monitor.git"
            "repo_name"             = "os.infra.monitor"
            "docker_registry"       = "docker_hub"
            "docker_registry_image" = "jestrr/monitor"
            "docker_registry_url"   = ""
            "docker_registry_user"  = ""
            "docker_registry_pw"    = ""
            "service_name"          = "monitor"
            "green_service"         = "monitor_main"
            "blue_service"          = "monitor_dev"
            "default_active"        = "green"
            "create_subdomain"      = "true"  ## Also used for letsencrypt renewal
        }
    }
}

variable "misc_repos" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string,
        docker_service_name=string, consul_service_name=string, folder_location=string,
        logs_prefix=string, email_image=string
    }))
    default = {
        chef = {
            "pull"                  = "true"
            "stable_version"        = ""
            "use_stable"            = "false"
            "repo_url"              = "https://github.com/Cjones90/os.infra.chef.git"
            "repo_name"             = "os.infra.chef"

            # Temporary
            "docker_service_name"   = ""
            "consul_service_name"   = ""
            "folder_location"       = ""
            "logs_prefix"           = ""
            "email_image"           = ""
        }
    }
}
