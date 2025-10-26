########## Digital Ocean ##########
variable "do_region" { default = "nyc3" }

########## AWS ##########
variable "aws_region_alias" { default = "awseast" }
variable "aws_region" { default = "us-east-2" }
variable "aws_ecr_region" { default = "us-east-2" }
variable "placeholder_reusable_delegationset_id" { default = "" }

########## Azure ##########
variable "az_region" { default = "eastus" }
variable "az_resource_group" { default = "rg" }
variable "az_minio_gateway" { default = "" } #Defaults: localhost
variable "az_minio_gateway_port" { default = "" } #Defaults: 31900

########## MISC CONFIG/VARIABLES ##########
############################################
variable "stun_port" { default = 3478 }
## TODO: Can convert this into addition port -> svc mappings later
variable "kubernetes_nginx_nodeports" {
    default = {
        http = 32080
        https = 32443
        #udp = {
        #    3478 = "default/stun-app:3478"
        #    9000 = "udp_svc_namespace/udp_svc_name:3478"
        #}
        #tcp = {
        #    3478 = "default/stun-app:3478"
        #    9000 = "tcp_svc_namespace/tcp_svc_name:3478"
        #}
    }
}

## Name of gitlab dump file/tar minus "_gitlab_backup.tar"
## Default bucket location is ${local.env_bucket_prefix}-backups in global.appConfig.backups in gitlab module
## Previously used a bash script to loop through most recent - something like that again once helm backups working and stable
variable "gitlab_dump_name" { default = "" }
variable "gitlab_secrets_json" {
    default = {
        bucket = ""
        key = ""
    }
}
#TODO: Better handling of mirroring backup buckets
variable "source_env_bucket_prefix" { default = "" }
variable "target_env_bucket_prefix" { default = "" }
variable "gitlab_enabled" { default = false }
## TODO: Probably make import_gitlab an object with secrets, dump, version etc
variable "import_gitlab" { default = false }
variable "import_gitlab_version" { default = "" }

variable "mattermost_backups_enabled" { default = false }  #auto false if not "default" workspace
variable "gitlab_backups_enabled" { default = false }  #auto false if not "default" workspace
variable "install_unity3d" { default = false }

variable "buildkitd_namespace" { default = "buildkitd" }
variable "cleanup_kube_volumes" { default = true } #auto false if  "default" workspace
variable "helm_experiments" {
    default = false
    ephemeral = true
}
########## SOFTWARE VERSIONS ##########
#######################################

## TODO: Change this to helm chart version for services

##! NOTE: Software provisioned after launch
variable "nodeexporter_version" { default = "1.2.2" }
variable "promtail_version" { default = "2.4.1" }
variable "consulexporter_version" { default = "0.7.1" }
variable "loki_version" { default = "2.4.1" }
variable "buildkitd_version" { default = "0.10.5" }


##! kubernetes_version options: Valid version or recent version gitlab supports
##!   ex "1.24.7-00" | "gitlab"
#variable "kubernetes_version" { default = "gitlab" }
variable "kubernetes_version" { default = "1.33.1-00" }
#TODO: Hmm either helm chart version or gitlab version -> chart matrix
variable "gitlab_version" { default = "15.5.3-ce.0" }
variable "consul_version" { default = "1.10.3" } # Not sure consuls place in new infra yet


########## CLOUD MACHINES ##########
####################################

## NOTE: Feel lower dns ttl relevent when going from old non-managed k8s to new full k8s infra
##  so keeping this note to not forget it

###! TODO: Use to lower dns TTL to 60 seconds and perform all backups initially
###! Anything that is done pre-system/machine migration should be done in a
###!  run once (backups) or toggleable (dns TTL) fashion with this setting
#variable "migration_prep" { default = false } ## Not in use atm

# TODO: Google Cloud
# Options will be digital_ocean, aws, azure, google_cloud etc.
###! Current options: "digital_ocean", "aws", "azure"
variable "active_env_provider" { default = "digital_ocean" }
module "cloud" {
    source             = "../../modules/digital_ocean"  ###! Uncomment for digital ocean
    #source             = "../../modules/aws"          ###! Uncomment for aws
    #source             = "../../modules/azure"          ###! Uncomment for azure

    config = local.config
    helm_experiments = terraform.applying ? false : var.helm_experiments && fileexists("${path.module}/${terraform.workspace}-kube_config")
}

locals {
    kubeconfig_path = "${path.module}/${terraform.workspace}-kube_config"
    active_s3_provider = var.active_env_provider
    size_map = {
        ## TODO: Double check correlation with k8s managed node offerings over old static vm model
        xs = { aws = "t3a.micro", digital_ocean = "s-1vcpu-1gb", azure = "Standard_B1s" }
        s = { aws = "t3a.small", digital_ocean = "s-1vcpu-2gb", azure = "Standard_B1ms" }
        m = { aws = "t3a.small", digital_ocean = "s-2vcpu-2gb", azure = "Standard_B1ms" }
        l = { aws = "t3a.medium", digital_ocean = "s-2vcpu-4gb", azure = "Standard_B2s" }
        xl = { aws = "t3a.large", digital_ocean = "s-4vcpu-8gb", azure = "Standard_B2ms" }
    }
    size = {
        xs = local.size_map["xs"][var.active_env_provider]
        s = local.size_map["s"][var.active_env_provider]
        m = local.size_map["m"][var.active_env_provider]
        l = local.size_map["l"][var.active_env_provider]
        xl = local.size_map["xl"][var.active_env_provider]
    }
    ##! Used with `managed_kubernetes`
    ##! Only for digital ocean during alpha
    managed_kubernetes_conf = lookup(local.workspace_managed_kubernetes_conf, terraform.workspace, local.workspace_managed_kubernetes_conf["default"])
    gitlab_cluster = [
        { size = local.size["s"], count = 1, labels = {type = "main"} },
        { size = local.size["s"], auto_scale = true, min_nodes = 0, max_nodes = 4, key = "2gb-s" },
        { size = local.size["l"], auto_scale = true, min_nodes = 0, max_nodes = 2, labels = {type = "gitlab"} },
        { size = local.size["xl"], auto_scale = true, min_nodes = 0, max_nodes = 2, labels = {type = "gitlab-web"}, taints = {type = "gitlab-web"} },
    ]
    workspace_managed_kubernetes_conf = {
        "default" = [{
            #key        = "" ## Opt key if multiple node groups same size
            size       = local.size["m"]
            labels     = {type="main"}
            taints     = []

            ##! (count) or (min_node + max_node + auto_scale)
            count      = 0
            #min_nodes  = 0
            #max_nodes  = 0
            #auto_scale = true
        }]
        "gitlab-env" = local.gitlab_cluster
    }
}

############ DNS ############
#############################
variable "gitlab_subdomain" { default = "gitlab" }
# Used for gitlab oauth plugins
variable "mattermost_subdomain" { default = "chat" }
variable "wekan_subdomain" { default = "wekan" }

# CNAME record
variable "cname_aliases" {
    default = [
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

variable "offsite_arecord_aliases" {
    default = [ 
        #{ name = "", ip = "" }
    ]
}

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
