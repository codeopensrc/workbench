########## Digital Ocean ##########
variable "do_region" { default = "nyc3" }

########## AWS ##########
variable "aws_region_alias" { default = "awseast" }
variable "aws_region" { default = "us-east-2" }
variable "aws_ecr_region" { default = "us-east-2" }
variable "placeholder_reusable_delegationset_id" { default = "" }

########## MISC CONFIG/VARIABLES ##########
############################################
variable "stun_port" { default = "" }

variable "import_gitlab" { default = false }
variable "import_gitlab_version" { default = "" }

variable "gitlab_backups_enabled" { default = false }  #auto false if not "default" workspace
variable "install_unity3d" { default = false }

########## SOFTWARE VERSIONS ##########
#######################################
variable "packer_config" {
    default = {
        gitlab_version = "14.3.0-ce.0"
        docker_version = "20.10.7"
        docker_compose_version = "1.29.2"
        consul_version = "1.10.0"
        redis_version = "5.0.9"
        base_amis = {
            "us-east-2" = "ami-030bd1caa8425dfe8" #20.04
        }
        digitalocean_image_os = {
            "main" = "ubuntu-20-04-x64"
        }
    }
}

########## CLOUD MACHINES ##########
####################################

# TODO: Azure and Google Cloud providers
# Options will be digital_ocean, aws, azure, google_cloud etc.
###! Current options: "digital_ocean" or "aws"
variable "active_env_provider" { default = "digital_ocean" }
module "main" {
    source             = "../../modules/digital_ocean"  ###! Uncomment for digital ocean
    # source             = "../../modules/aws"          ###! Uncomment for aws

    config = local.config
}

###! When downsizing from 2 to 1 leader, set downsize = true, terraform apply. This adjusts app routing.
###! Then comment/remove 2nd server, downsize = false, and terraform apply again to remove it
variable "downsize" { default = false }

###! TODO: Use to lower dns TTL to 60 seconds and perform all backups initially
###! Anything that is done pre-system/machine migration should be done in a
###!  run once (backups) or toggleable (dns TTL) fashion with this setting
variable "migration_prep" { default = false } ## Not in use atm

## Known role support matrix for 1-3 nodes
## All matrices support adding multiple 1gb+ build nodes
## None of the matrices support more than 1 db role in a cluster
## None of the matrices support more than 1 admin role in a cluster

# 1 node  - (admin + lead + db)  -- Confirmed
# 1 node  - (lead + db)          -- Confirmed

# 2 nodes - (lead), (db)                 -- Confirmed
# 2 nodes - (lead + db), (lead)          -- Confirmed
# 2 nodes - (admin), (lead + db)         -- Confirmed
# 2 nodes - (admin + db), (lead)         -- Confirmed
# 2 nodes - (admin + lead), (db)         -- Confirmed
# 2 nodes - (admin + lead + db), (lead)  -- Confirmed

# 3 nodes - (lead), (lead), (db)                -- TO TEST
# 3 nodes - (lead + db), (lead), (lead)         -- TO TEST
# 3 nodes - (admin), (lead), (db)               -- Confirmed
# 3 nodes - (admin), (lead + db), (lead)        -- TO TEST
# 3 nodes - (admin + db), (lead), (lead)        -- Confirmed
# 3 nodes - (admin + lead), (lead), (db)        -- Confirmed
# 3 nodes - (admin + lead), (lead + db), (lead) -- TO TEST
# 3 nodes - (admin + lead + db), (lead), (lead) -- TO TEST


variable "servers" {
    ### NOTE: Do not add or remove roles from instances after they are launched
    default = [
        {
            "count" = 1
            "image" = ""
            "roles" = ["admin", "lead", "db"]
            # "roles" = ["admin"]
            "size" = {
                "aws" = ["t3a.micro", "t3a.small", "t3a.medium", "t3a.large"][3]
                "digital_ocean" = ["s-2vcpu-4gb", "s-4vcpu-8gb"][1]
            }
            "aws_volume_size" = 60
        },
        # {
        #     "count" = 1
        #     "image" = ""
        #     "roles" = ["lead"]
        #     "size" = {
        #         "aws" = ["t3a.micro", "t3a.small", "t3a.medium", "t3a.large"][1]
        #         "digital_ocean" = ["s-1vcpu-1gb", "s-1vcpu-2gb", "s-2vcpu-2gb", "s-2vcpu-4gb", "s-4vcpu-8gb"][0]
        #     }
        #     "aws_volume_size" = 40
        # },
        # {
        #     "count" = 1
        #     "image" = ""
        #     "roles" = ["db"]
        #     "size" = {
        #         "aws" = ["t3a.micro", "t3a.small", "t3a.medium", "t3a.large"][1]
        #         "digital_ocean" = ["s-1vcpu-1gb", "s-1vcpu-2gb", "s-2vcpu-2gb", "s-2vcpu-4gb", "s-4vcpu-8gb"][0]
        #     }
        #     "aws_volume_size" = 40
        # },
        # {
        #     "count" = 1
        #     "image" = ""
        #     "roles" = ["build"]
        #     "size" = {
        #         "aws" = ["t3a.micro", "t3a.small", "t3a.medium", "t3a.large"][1]
        #         "digital_ocean" = ["s-1vcpu-1gb", "s-1vcpu-2gb", "s-2vcpu-2gb", "s-2vcpu-4gb", "s-4vcpu-8gb"][0]
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
    ]
        #"btcpay"
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
    default = [ "*.dev", "*.beta" ]
}

variable "additional_ssl" {
    default = [
        #{
        #    create_ssl_cert = true
        #    create_dev_dns = true
        #    subdomain_name = ""
        #    service_name = ""
        #}
    ]
}

variable "offsite_arecord_aliases" {
    default = [ 
        #{
        #    name = "",
        #    ip = "",
        #}
    ]
}

##NOTE: ATM requires a server with gitlab+nginx+admin role
variable "additional_domains" {
    default = {
        #"domain.com" = {
        #    "@" = "https://someotherdomain.com"
        #    "apisubdomain" = "https://externalapi.com"
        #    #"@" = "A"
        #    #"www" = "CNAME"
        #}
    }
}

variable "misc_repos" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string, docker_registry_image=string,
        docker_service_name=string, consul_service_name=string, folder_location=string,
        logs_prefix=string, email_image=string
    }))
    default = {}
}
