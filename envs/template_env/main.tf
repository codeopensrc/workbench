###################################
####### Variables in this file and inside modules not intended to be modified
###################################
#### Only apps.tf, credentials.tf, and vars.tf should be modified
###################################

output "cluster" {
    sensitive = true
    value = module.cloud.cluster_info
}

## NOTE: Think token has a 7 day expiry
resource "local_file" "kube_config" {
    content  = module.cloud.cluster_info.kube_config.raw_config
    filename = local.kubeconfig_path
}

##NOTE: Uses ansible
##TODO: Figure out how best to organize modules/playbooks/hostfile
#module "init" {
#    source = "../../modules/init"
#    depends_on = [
#        module.cloud,
#        module.ansible,
#    ]
#    ansible_hosts = local.ansible_hosts
#    ansible_hostfile = local.ansible_hostfile
#    remote_state_hosts = local.remote_state_hosts
#
#    server_count = local.server_count
#
#    region = local.region
#    server_name_prefix = local.server_name_prefix
#    root_domain_name = local.root_domain_name
#    hostname = "${var.gitlab_subdomain}.${local.root_domain_name}"
#
#    do_spaces_region = var.do_spaces_region
#    do_spaces_access_key = var.do_spaces_access_key
#    do_spaces_secret_key = var.do_spaces_secret_key
#
#    aws_bot_access_key = var.aws_bot_access_key
#    aws_bot_secret_key = var.aws_bot_secret_key
#
#    az_storageaccount = var.az_storageaccount
#    az_storagekey = var.az_storagekey
#    az_minio_gateway = var.az_minio_gateway
#    az_minio_gateway_port = var.az_minio_gateway_port
#
#    known_hosts = var.known_hosts
#    deploy_key_location = var.deploy_key_location
#
#    nodeexporter_version = var.nodeexporter_version
#    promtail_version = var.promtail_version
#    consulexporter_version = var.consulexporter_version
#    loki_version = var.loki_version
#
#    pg_read_only_pw = var.pg_read_only_pw
#    postgres_version = var.postgres_version
#    postgres_port = var.postgres_port
#    mongo_version = var.mongo_version
#    mongo_port = var.mongo_port
#    redis_version = var.redis_version
#    redis_port = var.redis_port
#}

##NOTE: Uses ansible
##TODO: Figure out how best to organize modules/playbooks/hostfile
#module "consul" {
#    source = "../../modules/consul"
#    depends_on = [
#        module.cloud,
#        module.ansible,
#        module.init,
#    ]
#    ansible_hosts = local.ansible_hosts
#    ansible_hostfile = local.ansible_hostfile
#    predestroy_hostfile = local.predestroy_hostfile
#    remote_state_hosts = local.remote_state_hosts
#
#    region = local.region
#    server_count = local.server_count
#
#    app_definitions = var.app_definitions
#    additional_ssl = var.additional_ssl
#    root_domain_name = local.root_domain_name
#    pg_password = var.pg_password
#    dev_pg_password = var.dev_pg_password
#
#    ## Deletes /etc/consul.d/data datadir
#    ## Only use for testing/recovering from severely broken consul cluster config
#    force_consul_rebootstrap = false
#}

##NOTE: Uses ansible
##TODO: Figure out how best to organize modules/playbooks/hostfile
#module "cron" {
#    source = "../../modules/cron"
#    depends_on = [
#        module.cloud,
#        module.ansible,
#        module.init,
#        module.consul,
#    ]
#    ansible_hosts = local.ansible_hosts
#    ansible_hostfile = local.ansible_hostfile
#    remote_state_hosts = local.remote_state_hosts
#
#    admin_servers = local.admin_servers
#    lead_servers = local.lead_servers
#    db_servers = local.db_servers
#
#    s3alias = local.s3alias
#    s3bucket = local.s3bucket
#    use_gpg = var.use_gpg
#    # Admin specific
#    gitlab_backups_enabled = var.gitlab_backups_enabled
#    # Leader specific
#    app_definitions = var.app_definitions
#    # DB specific
#    redis_dbs = local.redis_dbs
#    mongo_dbs = local.mongo_dbs
#    pg_dbs = local.pg_dbs
#}

resource "null_resource" "cleanup_gitlab_cluster_volumes" {
    count = terraform.workspace == "default" ? 0 : (var.gitlab_enabled ? 1 : 0)
    depends_on = [ local_file.kube_config, ]
    triggers = { kubeconfig_path = local.kubeconfig_path }

    ## Delete gitlab pvcs
    provisioner "local-exec" {
        when = destroy
        command = <<-EOF
        PVCS=$(kubectl get pvc -A -o custom-columns=NAME:.metadata.name,NS:.metadata.namespace --no-headers -l app.kubernetes.io/instance=gitlab | sed -r "s/\s+/ /g")
        if [ -n "$PVCS" ]; then
            echo "$PVCS" | while IFS= read -r PVC; do
                PVCNAME=$(echo "$PVC" | cut -d " " -f1)
                NS=$(echo "$PVC" | cut -d " " -f2)
                echo "Patching $PVCNAME in $NS"
                kubectl patch pvc $PVCNAME -n $NS -p '{"metadata":{"finalizers":null}}'
            done
        fi
        PVCS2=$(kubectl get pvc -A -o custom-columns=NAME:.metadata.name,NS:.metadata.namespace --no-headers -l release=gitlab | sed -r "s/\s+/ /g")
        if [ -n "$PVCS2" ]; then
            echo "$PVCS2" | while IFS= read -r PVC; do
                PVCNAME=$(echo "$PVC" | cut -d " " -f1)
                NS=$(echo "$PVC" | cut -d " " -f2)
                echo "Patching $PVCNAME in $NS"
                kubectl patch pvc $PVCNAME -n $NS -p '{"metadata":{"finalizers":null}}'
            done
        fi
        kubectl delete pvc --all -n gitlab
        EOF
        interpreter = ["/bin/bash", "-c"]
        environment = {
            KUBECONFIG = self.triggers.kubeconfig_path
        }
    }
}

module "gitlab" {
    source = "../../modules/gitlab"
    depends_on = [
        local_file.kube_config,
        null_resource.cleanup_gitlab_cluster_volumes,
        module.cloud,
    ]
    local_init_filepath = local.init_filepath
    local_kubeconfig_path = local.kubeconfig_path
    root_domain_name = local.root_domain_name
    contact_email = var.contact_email

    gitlab_enabled = var.gitlab_enabled
    import_gitlab = var.import_gitlab
    import_gitlab_version = var.import_gitlab_version
    imported_runner_token = local.gitlab_runner_tokens

    use_gpg = var.use_gpg
    bot_gpg_name = var.bot_gpg_name

    #s3alias = local.s3alias
    #s3bucket = local.s3bucket

    mattermost_subdomain = var.mattermost_subdomain
    wekan_subdomain = var.wekan_subdomain

    gitlab_dump_name = var.gitlab_dump_name
    gitlab_secrets_body = module.cloud.gitlab_secrets_body
    gitlab_bucket_prefix = local.gitlab_bucket_prefix
    s3_region = local.region
    s3_access_key_id = local.s3accesskey
    s3_secret_access_key = local.s3secretkey
    s3_endpoint = local.s3endpoint
}

resource "gitlab_application_settings" "this" {
    depends_on = [
        local_file.kube_config,
        null_resource.cleanup_gitlab_cluster_volumes,
        module.cloud,
        module.gitlab,
    ]
    signup_enabled = false
    allow_runner_registration_token = true
}

##NOTE: Uses ansible
##TODO: Figure out how best to organize modules/playbooks/hostfile
#module "cirunners" {
#    source = "../../modules/cirunners"
#    depends_on = [
#        module.cloud,
#        module.ansible,
#        module.init,
#        module.consul,
#        module.cron,
#        module.gpg,
#        module.gitlab,
#        module.nginx,
#        module.clusterdb,
#        module.docker,
#        module.letsencrypt,
#    ]
#
#    ansible_hosts = local.ansible_hosts
#    ansible_hostfile = local.ansible_hostfile
#    predestroy_hostfile = local.predestroy_hostfile
#
#    gitlab_runner_tokens = local.gitlab_runner_tokens
#
#    build_servers = local.build_servers
#
#    runners_per_machine = local.num_runners_per_machine
#    root_domain_name = local.root_domain_name
#}

#resource "null_resource" "install_unity" {
#    count = var.install_unity3d ? local.build_servers : 0
#    depends_on = [ module.cirunners ]
#
#    provisioner "file" {
#        ## TODO: Unity version root level. Get year from version
#        source = "../../modules/packer/ignore/Unity_v2020.x.ulf"
#        destination = "/root/code/scripts/misc/Unity_v2020.x.ulf"
#    }
#
#    provisioner "remote-exec" {
#        ## TODO: Unity version root level.
#        inline = [
#            "cd /root/code/scripts/misc",
#            "chmod +x installUnity3d.sh",
#            "bash installUnity3d.sh -c c53830e277f1 -v 2020.2.7f1 -y" #TODO: Auto input "yes" if license exists
#        ]
#        #Cleanup anything no longer needed
#    }
#
#    connection {
#        host = element(local.build_public_ips, count.index)
#        type = "ssh"
#    }
#}

## Create the wekan and mattermost apps in a fresh install
## Think we'll have to delete all gitlab oauth apps when restoring
##TODO: Yes delete on restore - has to be done via api, names dont have to be unique
resource "gitlab_application" "oidc" {
    for_each = {
        for key, app in local.gitlab_oauth_apps: key => app
        if var.gitlab_enabled && app.enabled
    }
    depends_on = [
        module.cloud,
        module.gitlab,
    ]
    confidential = true
    scopes       = each.value.scopes
    name         = "${each.key}_plugin"
    redirect_url = each.value.redirect_url
}

resource "null_resource" "cleanup_app_cluster_volumes" {
    count = terraform.workspace == "default" ? 0 : 1
    depends_on = [ local_file.kube_config, ]
    triggers = { kubeconfig_path = local.kubeconfig_path }

    ## Delete non-gitlab pvcs
    provisioner "local-exec" {
        when = destroy
        command = <<-EOF
        PVCS=$(kubectl get pvc -A -o custom-columns=NAME:.metadata.name,NS:.metadata.namespace --no-headers -l app.kubernetes.io/instance!=gitlab,release!=gitlab | sed -r "s/\s+/ /g")
        if [ -n "$PVCS" ]; then
            echo "$PVCS" | while IFS= read -r PVC; do
                PVCNAME=$(echo "$PVC" | cut -d " " -f1)
                NS=$(echo "$PVC" | cut -d " " -f2)
                echo "Patching $PVCNAME in $NS"
                kubectl patch pvc $PVCNAME -n $NS -p '{"metadata":{"finalizers":null}}'
            done
        fi
        kubectl delete pvc --all-namespaces --field-selector metadata.namespace!=gitlab
        EOF
        interpreter = ["/bin/bash", "-c"]
        environment = {
            KUBECONFIG = self.triggers.kubeconfig_path
        }
    }
}

module "kubernetes" {
    source = "../../modules/kubernetes"
    depends_on = [
        local_file.kube_config,
        null_resource.cleanup_app_cluster_volumes,
        module.cloud,
    ]
    oauth = gitlab_application.oidc
    subdomains = local.subdomains
    local_kubeconfig_path = local.kubeconfig_path

    gitlab_runner_tokens = local.gitlab_runner_tokens
    root_domain_name = local.root_domain_name
    contact_email = var.contact_email
    import_gitlab = var.import_gitlab
    vpc_private_iface = local.vpc_private_iface
    active_env_provider = var.active_env_provider

    kubernetes_version = local.kubernetes_version
    buildkitd_version = var.buildkitd_version
    cleanup_kube_volumes = local.cleanup_kube_volumes

    cloud_provider = local.cloud_provider
    cloud_provider_token = local.cloud_provider_token
    csi_namespace = local.csi_namespace
    csi_version = local.csi_version

    kube_apps = var.kube_apps
    kube_services = var.kube_services
    kubernetes_nginx_nodeports = var.kubernetes_nginx_nodeports

    gitlab_bucket_prefix = local.gitlab_bucket_prefix
    s3_region = local.region
    s3_access_key_id = local.s3accesskey
    s3_secret_access_key = local.s3secretkey
    s3_endpoint = local.s3endpoint
    s3_backup_bucket = local.s3_backup_bucket
}

resource "local_file" "init" {
    count = var.gitlab_enabled ? 1 : 0
    depends_on = [ module.gitlab ]
    content  = "true"
    filename = local.init_filepath
}

#resource "null_resource" "configure_smtp" {
#    count = local.admin_servers
#    depends_on = [
#        module.cloud,
#        module.ansible,
#        module.init,
#        module.consul,
#        module.cron,
#        module.gpg,
#        module.gitlab,
#        module.nginx,
#        module.clusterdb,
#        module.docker,
#        module.letsencrypt,
#        module.cirunners,
#        null_resource.install_unity,
#        module.kubernetes,
#    ]
#
#    provisioner "file" {
#        content = <<-EOF
#            SENDGRID_KEY=${local.sendgrid_apikey}
#
#            if [ -n "$SENDGRID_KEY" ]; then
#                bash $HOME/code/scripts/misc/configureSMTP.sh -k ${local.sendgrid_apikey} -d ${local.sendgrid_domain};
#            else
#                bash $HOME/code/scripts/misc/configureSMTP.sh -d ${local.root_domain_name};
#            fi
#        EOF
#        destination = "/tmp/configSMTP.sh"
#    }
#    provisioner "remote-exec" {
#        inline = [
#            "chmod +x /tmp/configSMTP.sh",
#            "bash /tmp/configSMTP.sh",
#            "rm /tmp/configSMTP.sh"
#        ]
#    }
#
#    connection {
#        host = element(local.admin_public_ips, 0)
#        type = "ssh"
#    }
#}


locals {
    ###! provider based
    vpc_private_iface = local.vpc_private_ifaces[var.active_env_provider]
    s3alias = local.s3aliases[local.active_s3_provider]
    s3bucket = local.s3buckets[local.active_s3_provider]
    s3accesskey = local.s3accesskeys[local.active_s3_provider]
    s3secretkey = local.s3secretkeys[local.active_s3_provider]
    s3endpoint = local.s3endpoints[local.active_s3_provider]
    region = local.regions[var.active_env_provider]
    cloud_provider = local.cloud_providers[var.active_env_provider]
    cloud_provider_token = local.cloud_provider_tokens[var.active_env_provider]
    csi_namespace = local.csi_namespaces[var.active_env_provider]
    csi_version = local.csi_versions[var.active_env_provider]
    lb_name = local.lb_names[var.active_env_provider]
    init_filepath = "${path.module}/${terraform.workspace}-infra-init"

    vpc_private_ifaces = {
        "digital_ocean" = "eth1"
        "aws" = "ens5"
        "azure" = "eth0"
    }
    s3accesskeys = {
        "digital_ocean" = var.do_spaces_access_key
        "aws" = var.aws_bot_access_key
        "azure" = var.az_storageaccount
    }
    s3secretkeys = {
        "digital_ocean" = var.do_spaces_secret_key
        "aws" = var.aws_bot_secret_key
        "azure" = var.az_storagekey
    }
    s3aliases = {
        "digital_ocean" = "spaces"
        "aws" = "s3"
        "azure" = "azure"
    }
    s3buckets = {
        "digital_ocean" = var.do_spaces_name
        "aws" = var.aws_bucket_name
        "azure" = var.az_bucket_name
    }
    s3endpoints = {
        "digital_ocean" = "https://${local.region}.digitaloceanspaces.com"
        "aws" = ""
        "azure" = ""
    }
    regions = {
        "digital_ocean" = var.do_region
        "aws" = var.aws_region_alias
        "azure" = var.az_region
    }
    cloud_providers = {
        "digital_ocean" = "digitalocean"
        "aws" = ""
        "azure" = ""
    }
    cloud_provider_tokens = {
        "digital_ocean" = var.do_token
        "aws" = ""
        "azure" = ""
    }
    csi_namespaces = {
        "digital_ocean" = "kube-system"
        "aws" = ""
        "azure" = ""
    }
    csi_versions = {
        "digital_ocean" = local.kube_do_csi_version
        "aws" = ""
        "azure" = ""
    }
    lb_names = {
        "digital_ocean" = "${local.server_name_prefix}-${local.region}-lb"
        "aws" = ""
        "azure" = ""
    }


    ###! workspace based
    additional_domains = terraform.workspace == "default" ? var.additional_domains : {}

    gitlab_runner_tokens = var.import_gitlab ? local.gitlab_runner_registration_tokens.service : ""

    gitlab_oauth_apps = { 
        wekan = {
            enabled = var.kube_services["wekan"].enabled
            redirect_url = "https://${var.wekan_subdomain}.${local.root_domain_name}/_oauth/oidc"
            scopes = ["openid", "profile", "email"]
        }
        ## Gitlab SSO https://docs.mattermost.com/administration-guide/configure/authentication-configuration-settings.html#enable-oauth-2-0-authentication-with-gitlab
        mattermost = {
            enabled = var.kube_services["mattermost"].enabled
            redirect_url = "https://${var.mattermost_subdomain}.${local.root_domain_name}/login/gitlab/complete\r\nhttps://${var.mattermost_subdomain}.${local.root_domain_name}/signup/gitlab/complete"
            scopes = ["api"]
        }
        ## Gitlab integration in mattermost https://docs.mattermost.com/integrations-guide/gitlab.html
        mattermost_integration = {
            enabled = var.kube_services["mattermost"].enabled
            redirect_url = "https://${var.mattermost_subdomain}.${local.root_domain_name}/plugins/com.github.manland.mattermost-plugin-gitlab/oauth/complete"
            scopes = ["api", "read_user"]
        }
    }
    subdomains = {
        wekan = var.wekan_subdomain
        mattermost = var.mattermost_subdomain
    }
    gitlab_kube_matrix = {
        "14.4.2-ce.0" = "1.20.11-00"
        "15.5.3-ce.0" = "1.24.7-00"
    }
    ## values() order output is based on SORTED gitlab_versions, then reversed
    last_gitlab_kube_version = reverse(values(local.gitlab_kube_matrix))[0]
    gitlab_major_minor = regex("^[0-9]+.[0-9]+", var.gitlab_version)
    kube_versions_found = [
        for GITLAB_V, KUBE_V in local.gitlab_kube_matrix: KUBE_V
        if length(regexall("^${local.gitlab_major_minor}", GITLAB_V)) > 0
    ]
    gitlab_kube_version = (var.kubernetes_version == "gitlab"
        ? ( lookup(local.gitlab_kube_matrix, var.gitlab_version, null) != null
            ? local.gitlab_kube_matrix[var.gitlab_version]
            : (length(local.kube_versions_found) > 0
                ? reverse(local.kube_versions_found)[0]
                : local.last_gitlab_kube_version) )
        : var.kubernetes_version)
    kubernetes_version = local.gitlab_kube_version

    kube_do_csi_matrix = {
        "1.20.11-00" = "3.0.0"
        "1.24.7-00"  = "4.3.0"
    }
    ## values() order output is based on SORTED kubernetes_versions, then reversed
    last_kube_do_csi_version = reverse(values(local.kube_do_csi_matrix))[0]
    kubernetes_major_minor = regex("^[0-9]+.[0-9]+", local.kubernetes_version)
    csi_versions_found = [
        for KUBE_V, CSI_V in local.kube_do_csi_matrix: CSI_V
        if length(regexall("^${local.kubernetes_major_minor}", KUBE_V)) > 0
    ]
    kube_do_csi_version = ( lookup(local.kube_do_csi_matrix, local.kubernetes_version, null) != null
        ? local.kube_do_csi_matrix[local.kubernetes_version]
        : (length(local.csi_versions_found) > 0
            ? reverse(local.csi_versions_found)[0]
            : local.last_kube_do_csi_version) )

    cleanup_kube_volumes = terraform.workspace == "default" ? false : var.cleanup_kube_volumes

    dbs_to_import = [
        for db in var.dbs_to_import: {
            for k, v in db: 
            k => (k == "s3alias" && v == "active_s3_provider" ? local.s3alias : v)
        }
    ]
    redis_dbs = [
        for db in local.dbs_to_import:
        {name = db.dbname, backups_enabled = db.backups_enabled}
        if db.type == "redis" && ( db.import == "true" || db.backups_enabled == "true" )
    ]
    pg_dbs = [
        for db in local.dbs_to_import:
        {name = db.dbname, backups_enabled = db.backups_enabled}
        if db.type == "pg" && ( db.import == "true" || db.backups_enabled == "true" )
    ]
    mongo_dbs = [
        for db in local.dbs_to_import:
        {name = db.dbname, backups_enabled = db.backups_enabled}
        if db.type == "mongo" && ( db.import == "true" || db.backups_enabled == "true" )
    ]
}

locals {
    ##! local.config is a wrapper to pass into module.cloud in vars.tf
    config = {
        ## Machine/Misc
        region = local.region
        server_name_prefix = local.server_name_prefix
        active_env_provider = var.active_env_provider
        local_ssh_key_file = var.local_ssh_key_file
        app_definitions = var.app_definitions
        managed_kubernetes_conf = local.managed_kubernetes_conf

        buildkitd_version = var.buildkitd_version
        buildkitd_namespace = var.buildkitd_namespace

        ## DNS
        root_domain_name = local.root_domain_name
        additional_domains = local.additional_domains
        cname_aliases = var.cname_aliases
        db_arecord_aliases = var.db_arecord_aliases
        offsite_arecord_aliases = var.offsite_arecord_aliases
        misc_cnames = concat([], local.misc_cnames)
        placeholder_reusable_delegationset_id = var.placeholder_reusable_delegationset_id

        ## Networking/VPC
        stun_port = var.stun_port
        docker_machine_ip = var.docker_machine_ip
        cidr_block = local.cidr_block
        app_ips = var.app_ips
        station_ips = var.station_ips
        cert_port = 7080
        kubernetes_nginx_nodeports = var.kubernetes_nginx_nodeports

        ## Credentials/Cloud
        contact_email = var.contact_email

        do_token = var.do_token
        do_spaces_access_key = var.do_spaces_access_key
        do_spaces_secret_key = var.do_spaces_secret_key
        do_region = var.do_region
        do_ssh_fingerprint = var.do_ssh_fingerprint
        do_lb_name = local.lb_name

        aws_key_name = var.aws_key_name
        aws_access_key = var.aws_access_key
        aws_secret_key = var.aws_secret_key
        aws_region = var.aws_region

        az_admin_username = var.az_admin_username
        az_subscriptionId = var.az_subscriptionId
        az_tenant = var.az_tenant
        az_appId = var.az_appId
        az_password = var.az_password
        az_region = var.az_region
        az_resource_group = var.az_resource_group

        kubernetes_version = var.kubernetes_version

        ## gitlab secrets
        gitlab_enabled = var.gitlab_enabled
        import_gitlab = var.import_gitlab
        gitlab_secrets_json = var.gitlab_secrets_json
        gitlab_bucket_prefix = local.gitlab_bucket_prefix
    }
}


####! TODO: Need to revisit cross DC communication at some point
