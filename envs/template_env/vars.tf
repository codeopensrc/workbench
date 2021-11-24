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
variable "postgres_port" { default = "5432" } ## Not fully implemented - consulchecks atm
variable "redis_port" { default = "6379" } ## Not fully implemented - consulchecks atm
variable "mongo_port" { default = "27017" } ## Not fully implemented - consulchecks atm

variable "import_gitlab" { default = false }
variable "import_gitlab_version" { default = "" }

variable "gitlab_backups_enabled" { default = false }  #auto false if not "default" workspace
variable "install_unity3d" { default = false }

## NOTE: Kubernetes admin requires 2 cores and 2 GB of ram
variable "container_orchestrators" { default = ["kubernetes", "docker_swarm"] }## kubernetes and/or docker_swarm

########## SOFTWARE VERSIONS ##########
#######################################
## Provisioned after launch
##NOTE: Latest kubernetes: 1.22.3-00
variable "kubernetes_version" { default = "1.20.11-00" }## Gitlab 14.3.0 supports kubernetes 1.20.11-00
variable "nodeexporter_version" { default = "1.2.2" }
variable "promtail_version" { default = "2.4.1" }
variable "consulexporter_version" { default = "0.7.1" }
variable "loki_version" { default = "2.4.1" }
variable "postgres_version" { default = "9.5" } ## Not fully implemented - consulchecks atm
variable "mongo_version" { default = "4.4.6" } ## Not fully implemented - consulchecks atm
variable "redis_version" { default = "5.0.9" } ## Not fully implemented - consulchecks atm

## Baked into image
variable "packer_config" {
    default = {
        gitlab_version = "14.4.2-ce.0"
        docker_version = "20.10.10"
        docker_compose_version = "1.29.2"
        consul_version = "1.10.3"
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
module "cloud" {
    source             = "../../modules/digital_ocean"  ###! Uncomment for digital ocean
    #source             = "../../modules/aws"          ###! Uncomment for aws

    config = local.config
}

###! TODO: Use to lower dns TTL to 60 seconds and perform all backups initially
###! Anything that is done pre-system/machine migration should be done in a
###!  run once (backups) or toggleable (dns TTL) fashion with this setting
#variable "migration_prep" { default = false } ## Not in use atm

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

# 3 nodes - (lead), (lead), (db)                -- Confirmed
# 3 nodes - (lead + db), (lead), (lead)         -- Confirmed
# 3 nodes - (admin), (lead), (db)               -- Confirmed
# 3 nodes - (admin), (lead + db), (lead)        -- Confirmed
# 3 nodes - (admin + db), (lead), (lead)        -- Confirmed
# 3 nodes - (admin + lead), (lead), (db)        -- Confirmed
# 3 nodes - (admin + lead), (lead + db), (lead) -- Confirmed
# 3 nodes - (admin + lead + db), (lead), (lead) -- Confirmed


## New long term goal - taint based replacement of nodes
## Number is how many machines you want. When you want to replace a node, you `terraform taint` it
## Terraform and ansible should handle the graceful replacement of that node after `terraform apply`
##   (Would need at least 2 of that type of fleet to do so gracefully)
## Should work as easily/seemlessly as docker and kubernetes replacing containers/pods
variable "servers" {
    ### NOTE: Do not add or remove roles from instances after they are launched
    ### Fleets differ by either roles, size, or to use a specific image
    ### When intending to replace machines instead of scaling up/down
    ###  - Add a fleet, `terraform apply`, remove the old fleet, `terraform apply`
    ###  - Supports replacing 'lead' and 'build' type fleets
    default = [
        {
            "count" = 1
            "image" = ""
            "roles" = ["admin", "lead", "db"]
            #"roles" = ["admin"]
            "size" = {
                "aws" = ["t3a.micro", "t3a.small", "t3a.medium", "t3a.large"][3]
                "digital_ocean" = ["s-2vcpu-4gb", "s-4vcpu-8gb"][1]
            }
            "aws_volume_size" = 60
            "fleet" = "aurora"
        },
        {
            "count" = 0
            "image" = ""
            "roles" = ["lead"]
            "size" = {
                "aws" = ["t3a.micro", "t3a.small", "t3a.medium", "t3a.large"][1]
                "digital_ocean" = ["s-1vcpu-1gb", "s-1vcpu-2gb", "s-2vcpu-2gb", "s-2vcpu-4gb", "s-4vcpu-8gb"][0]
            }
            "aws_volume_size" = 40
            "fleet" = "lucy"
        },
        {
            "count" = 0
            "image" = ""
            "roles" = ["db"]
            "size" = {
                "aws" = ["t3a.micro", "t3a.small", "t3a.medium", "t3a.large"][1]
                "digital_ocean" = ["s-1vcpu-1gb", "s-1vcpu-2gb", "s-2vcpu-2gb", "s-2vcpu-4gb", "s-4vcpu-8gb"][0]
            }
            "aws_volume_size" = 40
            "fleet" = "daisy"
        },
        {
            "count" = 0
            "image" = ""
            "roles" = ["build"]
            "size" = {
                "aws" = ["t3a.micro", "t3a.small", "t3a.medium", "t3a.large"][1]
                "digital_ocean" = ["s-1vcpu-1gb", "s-1vcpu-2gb", "s-2vcpu-2gb", "s-2vcpu-4gb", "s-4vcpu-8gb"][0]
            }
            "aws_volume_size" = 40
            "fleet" = "beth"
        },
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
