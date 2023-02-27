# Local location for the private key to upload to the remote server
# This should be a unique ssh key only used to read private repositories using
#  either githubs deploy keys or bitbuckets access keys or gitlabs deploy keys/token
# Each private repo needs the PUBLIC version of this PRIVATE keyfile already added
# TODO: Optional/make as a map, repo -> keyfile etc.
# NOTE: Gitlab has deploy tokens but without a docker credential manager, a Personal Access token
#  is the best option as each docker login with token overwrites the previous credentials
variable "deploy_key_location" { default = "~/.ssh/repo_read" }

variable "known_hosts" {
    type = list(object({ site=string, pubkey=string }))
    default = [
        {
            site = ""
            pubkey = ""
        }
    ]
}

variable "app_ips" {
    type = list(object({ name=string, ip=string }))
    default = [
        {name = "example_app_public_ip", ip = "123.123.123.123"},
    ]
}

variable "station_ips" {
    type = list(object({ name=string, ip=string }))
    default = [
        {name = "example_workstation_public_ip", ip = "123.123.123.123"},
    ]
}

############## DB ###########
#############################

variable "import_dbs" { default = true }

## Supports types "mongo", "redis", and "pg"
variable "dbs_to_import" {
    type = list(object({ type=string, s3bucket=string, s3alias=string,
        dbname=string, import=string, backups_enabled=string, fn=string }))  # TODO: "fn" hack
    default = [
        {
            "type" = "mongo"
            "s3bucket" = "S3_BUCKET_NAME"
            "s3alias" = "active_s3_provider" ##! s3 OR spaces OR azure OR active_s3_provider
            "dbname" = "wekan"
            "import" = "false"
            "backups_enabled" = "false"  ## auto false if not "default" workspace
            "fn" = ""
        }
    ]
}


########## APPS ##########
########################

## Migrating from app_definitions to kube_apps
## Eventually we'll update our apps to properly use ingress and cloud load balancers once we're
##  ready to fork up the extra pocket money for dev.
## Until then the dns for these will be populated using var.additional_ssl in vars.tf
## These are to be installed via helm in modules/kubernetes/playbooks/services.yml
variable "kube_apps" {
    type = map(object({
        repo_url=string, repo_name=string, image_tag=string,
        chart_url=string, chart_version=string,
    }))

    default = {
        template = {
            "image_tag"   = "0.0.1"
            "repo_url"    = "https://github.com/USER/REPO.git"
            "repo_name"   = "REPO"
            "chart_url"     = ""
            "chart_version" = ""
        }
    }
}

## Services running in the cluster to be consumed by other services
variable "kube_services" {
    type = map(object({
        chart=string, namespace=string, enabled=bool,
        chart_url=string, chart_version=string, opt_value_files=list(string)
    }))

    default = {
        prometheus = {
            "enabled"         = true
            "chart"           = "prometheus"
            "namespace"       = "monitoring"
            "chart_url"       = "https://prometheus-community.github.io/helm-charts"
            "chart_version"   = "19.6.1"
            "opt_value_files" = ["prometheus-values.yaml"]
        }
    }
}

# TODO: Digital Ocean, Azure, and Google Cloud docker registry options
# Initial Options: docker_hub, aws_ecr
# Aditional Options will be: digital_ocean_registry, azure, google_cloud
variable "app_definitions" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string, docker_registry=string, docker_registry_image=string,
        docker_registry_url=string, docker_registry_user=string, docker_registry_pw=string, service_name=string,
        green_service=string, blue_service=string, default_active=string,
        create_dns_record=string, create_dev_dns=string, create_ssl_cert=string, subdomain_name=string,
        use_custom_backup=string, custom_backup_file=string, backup_frequency=string,
        use_custom_restore=string, custom_restore_file=string, custom_init=string, custom_vars=string
    }))

    default = {
        # template = {
        #     "pull"                  = "true"
        #     "stable_version"        = "0.0.1"
        #     "use_stable"            = "false"
        #     "repo_url"              = "https://github.com/USER/REPO.git"
        #     "repo_name"             = "REPO"
        #     "docker_registry"       = "docker_hub"
        #     "docker_registry_image" = "ORG/IMAGE"
        #     "docker_registry_url"   = ""
        #     "docker_registry_user"  = ""
        #     "docker_registry_pw"    = ""
        #     "service_name"          = "sample"          ## Docker/Consul service name
        #     "green_service"         = "sample_main"     ## Docker/Consul service name
        #     "blue_service"          = "sample_dev"      ## Docker/Consul service name
        #     "default_active"        = "green"
        #     "create_dns_record"     = "true"    ## Affects dns and letsencrypt
        #     "create_dev_dns"        = "true"    ## Affects dns and letsencrypt
        #     "create_ssl_cert"       = "true"    ## Affects dns and letsencrypt
        #     "subdomain_name"        = "www"     ## Affects dns and letsencrypt
        #     "use_custom_backup"     = "false"
        #     "custom_backup_file"    = ""
        #     "backup_frequency"      = ""
        #     "use_custom_restore"    = "false"
        #     "custom_restore_file"   = ""
        #     "custom_init"           = ""
        #     "custom_vars"           = ""# <<-EOF EOF
        # }
        wekan = {
            "pull"                  = "true"
            "stable_version"        = "v5.35"
            "use_stable"            = "false"
            "repo_url"              = "https://gitlab.codeopensrc.com/os/wekan.git"
            "repo_name"             = "wekan"
            "docker_registry"       = "docker_hub"
            "docker_registry_image" = "wekanteam/wekan"
            "docker_registry_url"   = ""
            "docker_registry_user"  = ""
            "docker_registry_pw"    = ""
            "service_name"          = "wekan"              ## Docker/Consul service name
            "green_service"         = "wekan_main:4110"    ## Docker/Consul service name
            "blue_service"          = "wekan_dev"          ## Docker/Consul service name
            "default_active"        = "green"
            "create_dns_record"     = "true"    ## Affects dns and letsencrypt
            "create_dev_dns"        = "false"    ## Affects dns and letsencrypt
            "create_ssl_cert"       = "true"    ## Affects dns and letsencrypt
            "subdomain_name"        = "wekan"       ## Affects dns and letsencrypt
            "use_custom_backup"     = "false"
            "custom_backup_file"    = ""
            "backup_frequency"      = ""
            "use_custom_restore"    = "false"
            "custom_restore_file"   = ""
            "custom_init"           = ""
            "custom_vars"           = ""# <<-EOF EOF
        }
    }
}
