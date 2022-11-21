########## Digital Ocean ##########
variable "do_region" { default = "nyc3" }
variable "digitalocean_image_os" {
    default = {
        "nyc3" = "ubuntu-22-04-x64"
    }
}

########## AWS ##########
variable "aws_region_alias" { default = "awseast" }
variable "aws_region" { default = "us-east-2" }
variable "aws_ecr_region" { default = "us-east-2" }
variable "placeholder_reusable_delegationset_id" { default = "" }
variable "base_amis" {
    default = {
        "us-east-2" = "ami-030bd1caa8425dfe8" #20.04
    }
}

########## Azure ##########
variable "az_region" { default = "eastus" }
variable "az_resource_group" { default = "rg" }
variable "az_minio_gateway" { default = "" } #Defaults: localhost
variable "az_minio_gateway_port" { default = "" } #Defaults: 31900
variable "azure_image_os" {
    default = {
        "eastus" = {
            publisher = "Canonical"
            offer     = "UbuntuServer"
            sku       = "18.04-LTS"
            version   = "latest"
        }
    }
}

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
variable "container_orchestrators" {
    default = [
        "kubernetes",
        "docker_swarm",
        #"managed_kubernetes",  ## in alpha
    ]
}

variable "cleanup_kube_volumes" { default = true } #auto false if  "default" workspace
########## SOFTWARE VERSIONS ##########
#######################################

##! NOTE: Software provisioned after launch
variable "nodeexporter_version" { default = "1.2.2" }
variable "promtail_version" { default = "2.4.1" }
variable "consulexporter_version" { default = "0.7.1" }
variable "loki_version" { default = "2.4.1" }
variable "postgres_version" { default = "9.5" } ## Not fully implemented - consulchecks atm
variable "mongo_version" { default = "4.4.6" } ## Not fully implemented - consulchecks atm


##! NOTE: Packer config variables - Software baked into image
##! kubernetes_version options: Valid version, recent version gitlab supports, or latest
##!   ex "1.24.7-00" | "gitlab" | "" (empty/latest uses latest)
variable "kubernetes_version" { default = "gitlab" }
variable "gitlab_version" { default = "15.5.3-ce.0" }
variable "docker_version" { default = "20.10.21" }
variable "buildctl_version" { default = "0.10.5" }
variable "buildkitd_version" { default = "0.10.5" }
variable "consul_version" { default = "1.10.3" }
variable "redis_version" { default = "5.0.9" }
variable "helm_version" { default = "3.8.2-1" }  ## TODO kubernetes matrix
variable "skaffold_version" { default = "2.0.0" }


locals {
    packer_config = {
        gitlab_version = var.gitlab_version
        docker_version = var.docker_version
        buildctl_version = var.buildctl_version
        consul_version = var.consul_version
        redis_version = var.redis_version
        kubernetes_version = local.kubernetes_version
        helm_version = var.helm_version
        skaffold_version = var.skaffold_version
        base_amis = var.base_amis
        digitalocean_image_os = var.digitalocean_image_os
        azure_image_os = var.azure_image_os
    }
}

########## CLOUD MACHINES ##########
####################################

###! TODO: Use to lower dns TTL to 60 seconds and perform all backups initially
###! Anything that is done pre-system/machine migration should be done in a
###!  run once (backups) or toggleable (dns TTL) fashion with this setting
#variable "migration_prep" { default = false } ## Not in use atm

# Any combination of admin+lead+db+build on/across nodes works
# Only restriction for the moment is 1 admin role in a cluster (tied to gitlab)
#  Also its 1 OR 3+ db (2 is not HA)
# Cpu and memory issues should be taken into consideration
# DB and Build are kubernetes worker nodes, but so far 1gb *works*
# Lead are control-planes and work with 2gb nodes
# Admin currently installs gitlab and requires 8gb

# Migration/scaling of lead and db become HA at 3 nodes, with a 1 node malfunction toleration
# No extra configuration besides maybe redeployment of applications if deployed @ 2 nodes
# Admin/gitlab requires extra consideration in regards to migration and is not scalable atm


#####! For now replacing fleets instead of `terraform taint` works - See note @ `local.workspace_servers` below
## New long term goal - taint based replacement of nodes
## Number is how many machines you want. When you want to replace a node, you `terraform taint` it
## Terraform and ansible should handle the graceful replacement of that node after `terraform apply`
##   (Would need at least 2 of that type of fleet to do so gracefully)
## Should work as easily/seemlessly as docker and kubernetes replacing containers/pods

# TODO: Google Cloud
# Options will be digital_ocean, aws, azure, google_cloud etc.
###! Current options: "digital_ocean", "aws", "azure"
variable "active_env_provider" { default = "digital_ocean" }
module "cloud" {
    source             = "../../modules/digital_ocean"  ###! Uncomment for digital ocean
    #source             = "../../modules/aws"          ###! Uncomment for aws
    #source             = "../../modules/azure"          ###! Uncomment for azure

    config = local.config
}

locals {
    active_s3_provider = var.active_env_provider
    sizes = {
        "aws" = ["t3a.micro", "t3a.small", "t3a.small", "t3a.medium", "t3a.large"]
        "digital_ocean" = ["s-1vcpu-1gb", "s-1vcpu-2gb", "s-2vcpu-2gb", "s-2vcpu-4gb", "s-4vcpu-8gb"]
        "azure" = ["Standard_B1s", "Standard_B1ms", "Standard_B1ms", "Standard_B2s", "Standard_B2ms"]
    }
    ### NOTE: Do not add or remove roles from instances after they are launched
    ### Fleets differ by either roles, size, or to use a specific image
    ### When intending to replace machines instead of scaling up/down
    ###  - Add a fleet, `terraform apply`, remove the old fleet, `terraform apply`
    ###  - Supports replacing 'lead', 'build', 'db' type fleets
    servers = lookup(local.workspace_servers, terraform.workspace)
    ## NOTE: 'disk_size' applies to aws & azure only
    workspace_servers = {
        "default" = [
            {
                "count" = 1, "fleet" = "aurora", "roles" = ["admin", "lead", "db"], 
                "image" = "", "disk_size" = 60, "size" = local.sizes[var.active_env_provider][4], 
            },
            {
                "count" = 0, "fleet" = "lucy", "roles" = ["lead"],
                "image" = "", "disk_size" = 60, "size" = local.sizes[var.active_env_provider][0], 
            },
            {
                "count" = 0, "fleet" = "daisy", "roles" = ["db"], 
                "image" = "", "disk_size" = 60,"size" = local.sizes[var.active_env_provider][0], 
            },
            {
                "count" = 0, "fleet" = "beth", "roles" = ["build"],
                "image" = "", "disk_size" = 60, "size" = local.sizes[var.active_env_provider][0], 
            },
        ]
    }

    ##! Used with `managed_kubernetes`
    ##! Only for digital ocean during alpha
    managed_kubernetes_conf = lookup(local.workspace_managed_kubernetes_conf, terraform.workspace)
    workspace_managed_kubernetes_conf = {
        "default" = [{
            size       = "s-2vcpu-2gb"
            count = 0
            ##! (count) or (min_node + max_node + auto_scale)
            #min_nodes  = 0
            #max_nodes  = 0
            #auto_scale = true
        }]
    }
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
