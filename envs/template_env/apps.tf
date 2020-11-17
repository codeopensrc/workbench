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

# TODO: Digital Ocean, Azure, and Google Cloud docker registry options
# Initial Options: docker_hub, aws_ecr
# Aditional Options will be: digital_ocean_registry, azure, google_cloud
variable "app_definitions" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string, docker_registry=string, docker_registry_image=string,
        docker_registry_url=string, docker_registry_user=string, docker_registry_pw=string, service_name=string,
        green_service=string, blue_service=string, default_active=string, create_subdomain=string, subdomain_name=string,
        backup=string, backupfile=string
    }))

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
            "service_name"          = "proxy"       ## Docker/Consul service name
            "green_service"         = "proxy_main"  ## Docker/Consul service name
            "blue_service"          = "proxy_dev"   ## Docker/Consul service name
            "default_active"        = "green"
            "create_subdomain"      = "false"    ## Affects route53, consul, letsencrypt
            "subdomain_name"        = "proxy"     ## Affects route53, consul, letsencrypt
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
            "service_name"          = "monitor"         ## Docker/Consul service name
            "green_service"         = "monitor_main"    ## Docker/Consul service name
            "blue_service"          = "monitor_dev"     ## Docker/Consul service name
            "default_active"        = "green"
            "create_subdomain"      = "true"        ## Affects route53, consul, letsencrypt
            "subdomain_name"        = "monitor"     ## Affects route53, consul, letsencrypt
        }
        # stun = {
        #     "pull"                  = "true"
        #     "stable_version"        = "d2d06a6"
        #     "use_stable"            = "false"
        #     "repo_url"              = "https://gitlab.codeopensrc.com/os/stunserver.git"
        #     "repo_name"             = "stunserver"
        #     "docker_registry"       = ""
        #     "docker_registry_image" = "registry.codeopensrc.com/os/stunserver"
        #     "docker_registry_url"   = ""
        #     "docker_registry_user"  = ""
        #     "docker_registry_pw"    = ""
        #     "service_name"          = "stun"         ## Docker/Consul service name
        #     "green_service"         = "stun_main"    ## Docker/Consul service name
        #     "blue_service"          = "stun_dev"     ## Docker/Consul service name
        #     "default_active"        = "green"
        #     "create_subdomain"      = "false"    ## Affects route53, consul, letsencrypt
        #     "subdomain_name"        = "stun"     ## Affects route53, consul, letsencrypt
        # }
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
        #     "create_subdomain"      = "true"    ## Affects dns and letsencrypt
        #     "subdomain_name"        = "www"     ## Affects dns and letsencrypt
        # }
    }
}
