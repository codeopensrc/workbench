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
            "type" = "mongo"
            "aws_bucket" = "AWS_BUCKET_FOR_BACKUP"
            "aws_region" = "us-east-2"
            "dbname" = "wekan"
            "import" = "false"
            "fn" = ""
        }
    ]
}


########## APPS ##########
########################

# TODO: Digital Ocean, Azure, and Google Cloud docker registry options
# Initial Options: docker_hub, aws_ecr
# Aditional Options will be: digital_ocean_registry, azure, google_cloud
# TODO: Change "backup" to "use_backup_file" or make more granular per app instead
#    of global "db_backups_enabled"
variable "app_definitions" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string, docker_registry=string, docker_registry_image=string,
        docker_registry_url=string, docker_registry_user=string, docker_registry_pw=string, service_name=string,
        green_service=string, blue_service=string, default_active=string,
        create_dns_record=string, create_dev_dns=string, create_ssl_cert=string, subdomain_name=string,
        backup=string, backupfile=string, custom_init=string, custom_vars=string
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
        #     "backup"                = "false"
        #     "backupfile"            = ""
        #     "custom_init"           = ""
        #     "custom_vars"           = ""# <<-EOF EOF
        # }
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
        #     "create_dns_record"     = "false"    ## Affects dns and letsencrypt
        #     "create_dev_dns"        = "false"    ## Affects dns and letsencrypt
        #     "create_ssl_cert"       = "false"    ## Affects dns and letsencrypt
        #     "subdomain_name"        = "stun"     ## Affects dns and letsencrypt
        #     "backup"                = "false"
        #     "backupfile"            = ""
        #     "custom_init"           = ""
        #     "custom_vars"           = ""# <<-EOF EOF
        # }
        # btcpay = {
        #     "pull"                  = "true"
        #     "stable_version"        = ""
        #     "use_stable"            = "false"
        #     "repo_url"              = "https://gitlab.codeopensrc.com/os/btcpay.git"
        #     "repo_name"             = "btcpay"
        #     "docker_registry"       = ""
        #     "docker_registry_image" = ""
        #     "docker_registry_url"   = ""
        #     "docker_registry_user"  = ""
        #     "docker_registry_pw"    = ""
        #     "service_name"          = "custom"          ## Docker/Consul service name
        #     "green_service"         = "btcpay_main"     ## Docker/Consul service name
        #     "blue_service"          = "btcpay_dev"      ## Docker/Consul service name
        #     "default_active"        = "green"
        #     "create_dns_record"     = "false"    ## Affects dns and letsencrypt
        #     "create_dev_dns"        = "false"    ## Affects dns and letsencrypt
        #     "create_ssl_cert"       = "true"    ## Affects dns and letsencrypt
        #     "subdomain_name"        = "btcpay"     ## Affects dns and letsencrypt
        #     "backup"                = "false"
        #     "backupfile"            = ""
        #     "custom_init"           = "init.sh"
        #     "custom_vars"           = <<-EOF
        #         export BTCPAY_HOST=\"btcpay.EXAMPLE.COM\"
        #         export BTCPAYGEN_ADDITIONAL_FRAGMENTS=\"opt-save-storage-xxs\"
        #     EOF
        # }
        # wekan = {
        #     "pull"                  = "true"
        #     "stable_version"        = ""
        #     "use_stable"            = "false"
        #     "repo_url"              = "https://gitlab.codeopensrc.com/os/wekan.git"
        #     "repo_name"             = "wekan"
        #     "docker_registry"       = "docker_hub"
        #     "docker_registry_image" = "wekanteam/wekan"
        #     "docker_registry_url"   = ""
        #     "docker_registry_user"  = ""
        #     "docker_registry_pw"    = ""
        #     "service_name"          = "wekan"              ## Docker/Consul service name
        #     "green_service"         = "wekan_main:8080"    ## Docker/Consul service name
        #     "blue_service"          = "wekan_dev"          ## Docker/Consul service name
        #     "default_active"        = "green"
        #     "create_dns_record"     = "true"    ## Affects dns and letsencrypt
        #     "create_dev_dns"        = "true"    ## Affects dns and letsencrypt
        #     "create_ssl_cert"       = "true"    ## Affects dns and letsencrypt
        #     "subdomain_name"        = "wekan"       ## Affects dns and letsencrypt
        #     "backup"                = "false"
        #     "backupfile"            = ""
        #     "custom_init"           = ""
        #     "custom_vars"           = ""# <<-EOF EOF
        # }
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
            "create_dns_record"     = "false"    ## Affects dns and letsencrypt
            "create_dev_dns"        = "false"    ## Affects dns and letsencrypt
            "create_ssl_cert"       = "false"    ## Affects dns and letsencrypt
            "subdomain_name"        = "proxy"     ## Affects dns and letsencrypt
            "backup"                = "false"
            "backupfile"            = ""
            "custom_init"           = ""
            "custom_vars"           = ""# <<-EOF EOF
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
            "create_dns_record"     = "true"    ## Affects dns and letsencrypt
            "create_dev_dns"        = "true"    ## Affects dns and letsencrypt
            "create_ssl_cert"       = "true"    ## Affects dns and letsencrypt
            "subdomain_name"        = "monitor"     ## Affects dns and letsencrypt
            "backup"                = "false"
            "backupfile"            = ""
            "custom_init"           = ""
            "custom_vars"           = ""# <<-EOF EOF
        }
    }
}
