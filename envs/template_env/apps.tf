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
        enabled=bool, image_tag=string, repo_name=string, repo_url=string,
        release_name=string, chart_url=string, chart_version=string,
        chart_ref=string, namespace=string, create_namespace=bool,
        wait=bool, opt_value_files=list(string),
    }))

    default = {
        #example = {
        #    "enabled"          = false
        #    "image_tag"        = "0.0.1"
        #    "repo_name"        = "REPO"
        #    "repo_url"         = "https://github.com/USER/REPO.git"
        #    "release_name"     = "example"
        #    "chart_url"        = ""
        #    "chart_version"    = ""
        #    "chart_ref"        = "helmchart"
        #    "namespace"        = "default"
        #    "create_namespace" = true
        #    "wait"             = true
        #    "opt_value_files"  = ["example-values.yaml"]
        #},
        wekan = {
            "enabled"          = false
            "image_tag"        = "v5.35"
            "repo_name"        = "wekan"
            "repo_url"         = "https://gitlab.codeopensrc.com/os/wekan.git"
            "release_name"     = "wekan"
            "chart_url"        = ""
            "chart_version"    = ""
            "chart_ref"        = "charts/wekan"
            "namespace"        = "default"
            "create_namespace" = true
            "wait"             = true
            "opt_value_files"  = ["wekan-values.yaml"]
        },
        stun = {
            "enabled"          = false
            "image_tag"        = "d2d06a6"
            "repo_name"        = "stun"
            "repo_url"         = "https://gitlab.codeopensrc.com/os/stunserver.git"
            "release_name"     = "stun"
            "chart_url"        = ""
            "chart_version"    = ""
            "chart_ref"        = "charts/stun"
            "namespace"        = "default"
            "create_namespace" = true
            "wait"             = true
            "opt_value_files"  = ["stun-values.yaml"]
        },
    }
}

## Services running in the cluster to be consumed by other services
variable "kube_services" {
    default = {
        react = {
            "enabled"          = true
            "chart"            = "react"
            "namespace"        = "react"
            "create_namespace" = true
            "chart_url"        = "https://gitlab.codeopensrc.com/api/v4/projects/36/packages/helm/stable"
            "chart_version"    = "0.10.0"
            "opt_value_files"  = []
        }
        wekan = {
            "enabled"          = false
            "chart"            = "wekan"
            "namespace"        = "wekan"
            "create_namespace" = true
            "chart_url"        = "https://gitlab.codeopensrc.com/api/v4/projects/4/packages/helm/stable"
            "chart_version"    = "0.3.0"
            "opt_value_files"  = []
        },
        postgresql = {
            "enabled"          = true
            "chart"            = "postgresql"
            "namespace"        = "mattermost"
            "create_namespace" = false
            "chart_url"        = "https://charts.bitnami.com/bitnami"
            "chart_version"    = "16.7.27"
            "opt_value_files"  = []
        },
        mattermost = {
            "enabled"          = true
            "chart"            = "mattermost-operator"
            "namespace"        = "mattermost-operator"
            "create_namespace" = true
            "chart_url"        = "https://helm.mattermost.com"
            "chart_version"    = "1.0.4"
            "timeout"          = 120
            "opt_value_files"  = []
        },
        prometheus = {
            "enabled"          = false
            "chart"            = "prometheus"
            "namespace"        = "monitoring"
            "create_namespace" = true
            "chart_url"        = "https://prometheus-community.github.io/helm-charts"
            "chart_version"    = "19.6.1"
            "opt_value_files"  = ["prometheus-values.yaml"]
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
    }
}
