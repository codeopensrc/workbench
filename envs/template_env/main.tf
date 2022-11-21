###################################
####### Variables in this file and inside modules not intended to be modified
###################################
#### Only apps.tf, credentials.tf, and vars.tf should be modified
###################################

# `terraform output` for name and ip address of instances in state for env
output "instances" {
    value = module.cloud.instances
}

output "hosts" {
    value = module.cloud.ansible_hosts
    ## Marked as sensitive to squelch verbose output
    sensitive   = true
}

module "ansible" {
    source = "../../modules/ansible"
    depends_on = [ module.cloud ]

    ansible_hostfile = local.ansible_hostfile
    predestroy_hostfile = local.predestroy_hostfile
    ansible_hosts = local.ansible_hosts

    server_count = local.server_count
}

##NOTE: Uses ansible
##TODO: Figure out how best to organize modules/playbooks/hostfile
module "init" {
    source = "../../modules/init"
    depends_on = [
        module.cloud,
        module.ansible,
    ]
    ansible_hosts = local.ansible_hosts
    ansible_hostfile = local.ansible_hostfile
    remote_state_hosts = local.remote_state_hosts

    server_count = local.server_count

    region = local.region
    server_name_prefix = local.server_name_prefix
    root_domain_name = local.root_domain_name
    hostname = "${var.gitlab_subdomain}.${local.root_domain_name}"

    do_spaces_region = var.do_spaces_region
    do_spaces_access_key = var.do_spaces_access_key
    do_spaces_secret_key = var.do_spaces_secret_key

    aws_bot_access_key = var.aws_bot_access_key
    aws_bot_secret_key = var.aws_bot_secret_key

    az_storageaccount = var.az_storageaccount
    az_storagekey = var.az_storagekey
    az_minio_gateway = var.az_minio_gateway
    az_minio_gateway_port = var.az_minio_gateway_port

    known_hosts = var.known_hosts
    deploy_key_location = var.deploy_key_location

    nodeexporter_version = var.nodeexporter_version
    promtail_version = var.promtail_version
    consulexporter_version = var.consulexporter_version
    loki_version = var.loki_version

    pg_read_only_pw = var.pg_read_only_pw
    postgres_version = var.postgres_version
    postgres_port = var.postgres_port
    mongo_version = var.mongo_version
    mongo_port = var.mongo_port
    redis_version = var.redis_version
    redis_port = var.redis_port
}

##NOTE: Uses ansible
##TODO: Figure out how best to organize modules/playbooks/hostfile
module "consul" {
    source = "../../modules/consul"
    depends_on = [
        module.cloud,
        module.ansible,
        module.init,
    ]
    ansible_hosts = local.ansible_hosts
    ansible_hostfile = local.ansible_hostfile
    predestroy_hostfile = local.predestroy_hostfile
    remote_state_hosts = local.remote_state_hosts

    region = local.region
    server_count = local.server_count

    app_definitions = var.app_definitions
    additional_ssl = var.additional_ssl
    root_domain_name = local.root_domain_name
    pg_password = var.pg_password
    dev_pg_password = var.dev_pg_password

    ## Deletes /tmp/consul datadir
    ## Only use for testing/recovering from severely broken consul cluster config
    force_consul_rebootstrap = false
}

##NOTE: Uses ansible
##TODO: Figure out how best to organize modules/playbooks/hostfile
module "cron" {
    source = "../../modules/cron"
    depends_on = [
        module.cloud,
        module.ansible,
        module.init,
        module.consul,
    ]
    ansible_hosts = local.ansible_hosts
    ansible_hostfile = local.ansible_hostfile
    remote_state_hosts = local.remote_state_hosts

    admin_servers = local.admin_servers
    lead_servers = local.lead_servers
    db_servers = local.db_servers

    s3alias = local.s3alias
    s3bucket = local.s3bucket
    use_gpg = var.use_gpg
    # Admin specific
    gitlab_backups_enabled = var.gitlab_backups_enabled
    # Leader specific
    app_definitions = var.app_definitions
    # DB specific
    redis_dbs = local.redis_dbs
    mongo_dbs = local.mongo_dbs
    pg_dbs = local.pg_dbs
}

##NOTE: Uses ansible
##TODO: Figure out how best to organize modules/playbooks/hostfile
module "gpg" {
    source = "../../modules/gpg"
    count = var.use_gpg ? 1 : 0
    depends_on = [
        module.cloud,
        module.ansible,
        module.init,
        module.consul,
        module.cron,
    ]

    ansible_hosts = local.ansible_hosts
    ansible_hostfile = local.ansible_hostfile

    admin_servers = local.admin_servers
    db_servers = local.db_servers

    s3alias = local.s3alias
    s3bucket = local.s3bucket

    bot_gpg_name = var.bot_gpg_name
    bot_gpg_passphrase = var.bot_gpg_passphrase
}

module "gitlab" {
    source = "../../modules/gitlab"
    depends_on = [
        module.cloud,
        module.ansible,
        module.init,
        module.consul,
        module.cron,
        module.gpg,
    ]

    ansible_hosts = local.ansible_hosts
    ansible_hostfile = local.ansible_hostfile

    admin_servers = local.admin_servers
    server_count = local.server_count

    root_domain_name = local.root_domain_name
    contact_email = var.contact_email

    import_gitlab = var.import_gitlab
    import_gitlab_version = var.import_gitlab_version

    use_gpg = var.use_gpg
    bot_gpg_name = var.bot_gpg_name

    s3alias = local.s3alias
    s3bucket = local.s3bucket

    mattermost_subdomain = var.mattermost_subdomain
    wekan_subdomain = var.wekan_subdomain
}

##NOTE: Uses ansible
##TODO: Figure out how best to organize modules/playbooks/hostfile
module "nginx" {
    source = "../../modules/nginx"
    depends_on = [
        module.cloud,
        module.ansible,
        module.init,
        module.consul,
        module.cron,
        module.gpg,
        module.gitlab,
    ]
    ansible_hosts = local.ansible_hosts
    ansible_hostfile = local.ansible_hostfile

    lead_servers = local.lead_servers

    root_domain_name = local.root_domain_name
    app_definitions = var.app_definitions
    additional_domains = local.additional_domains
    additional_ssl = var.additional_ssl

    cert_port = local.config.cert_port
}

##NOTE: Uses ansible
##TODO: Figure out how best to organize modules/playbooks/hostfile
module "clusterdb" {
    source = "../../modules/clusterdb"
    depends_on = [
        module.cloud,
        module.ansible,
        module.init,
        module.consul,
        module.cron,
        module.gpg,
        module.gitlab,
        module.nginx,
    ]

    ansible_hosts = local.ansible_hosts
    ansible_hostfile = local.ansible_hostfile
    predestroy_hostfile = local.predestroy_hostfile
    remote_state_hosts = local.remote_state_hosts

    db_servers = local.db_servers

    redis_dbs = local.redis_dbs
    mongo_dbs = local.mongo_dbs
    pg_dbs = local.pg_dbs

    import_dbs = var.import_dbs
    dbs_to_import = local.dbs_to_import

    use_gpg = var.use_gpg
    bot_gpg_name = var.bot_gpg_name

    root_domain_name = local.root_domain_name
}

##NOTE: Uses ansible
##TODO: Figure out how best to organize modules/playbooks/hostfile
module "docker" {
    source = "../../modules/docker"
    depends_on = [
        module.cloud,
        module.ansible,
        module.init,
        module.consul,
        module.cron,
        module.gpg,
        module.gitlab,
        module.nginx,
        module.clusterdb,
    ]

    ansible_hosts = local.ansible_hosts
    ansible_hostfile = local.ansible_hostfile
    predestroy_hostfile = local.predestroy_hostfile
    remote_state_hosts = local.remote_state_hosts

    lead_servers = local.lead_servers

    region = local.region
    app_definitions = var.app_definitions
    aws_ecr_region   = var.aws_ecr_region

    container_orchestrators = var.container_orchestrators
}

resource "null_resource" "gpg_remove_key" {
    depends_on = [
        module.cloud,
        module.ansible,
        module.init,
        module.consul,
        module.cron,
        module.gpg,
        module.gitlab,
        module.nginx,
        module.clusterdb,
        module.docker,
    ]
    triggers = {
        admin_servers = local.admin_servers
        db_servers = local.db_servers
    }
    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ../../modules/gpg/playbooks/gpg_rmkey.yml -i ${local.ansible_hostfile} \
                --extra-vars "use_gpg=${var.use_gpg} bot_gpg_name=${var.bot_gpg_name}"
        EOF
    }
}

##NOTE: Uses ansible
##TODO: Figure out how best to organize modules/playbooks/hostfile
module "letsencrypt" {
    source = "../../modules/letsencrypt"
    depends_on = [
        module.cloud,
        module.ansible,
        module.init,
        module.consul,
        module.cron,
        module.gpg,
        module.gitlab,
        module.nginx,
        module.clusterdb,
        module.docker,
    ]

    ansible_hosts = local.ansible_hosts
    ansible_hostfile = local.ansible_hostfile

    lead_servers = local.lead_servers

    app_definitions = var.app_definitions
    additional_ssl = var.additional_ssl
    cert_port = local.config.cert_port

    root_domain_name = local.root_domain_name
    contact_email = var.contact_email
}

##NOTE: Uses ansible
##TODO: Figure out how best to organize modules/playbooks/hostfile
module "cirunners" {
    source = "../../modules/cirunners"
    depends_on = [
        module.cloud,
        module.ansible,
        module.init,
        module.consul,
        module.cron,
        module.gpg,
        module.gitlab,
        module.nginx,
        module.clusterdb,
        module.docker,
        module.letsencrypt,
    ]

    ansible_hosts = local.ansible_hosts
    ansible_hostfile = local.ansible_hostfile
    predestroy_hostfile = local.predestroy_hostfile

    gitlab_runner_tokens = local.gitlab_runner_tokens

    build_servers = local.build_servers

    runners_per_machine = local.num_runners_per_machine
    root_domain_name = local.root_domain_name
}

resource "null_resource" "install_unity" {
    count = var.install_unity3d ? local.build_servers : 0
    depends_on = [ module.cirunners ]

    provisioner "file" {
        ## TODO: Unity version root level. Get year from version
        source = "../../modules/packer/ignore/Unity_v2020.x.ulf"
        destination = "/root/code/scripts/misc/Unity_v2020.x.ulf"
    }

    provisioner "remote-exec" {
        ## TODO: Unity version root level.
        inline = [
            "cd /root/code/scripts/misc",
            "chmod +x installUnity3d.sh",
            "bash installUnity3d.sh -c c53830e277f1 -v 2020.2.7f1 -y" #TODO: Auto input "yes" if license exists
        ]
        #Cleanup anything no longer needed
    }

    connection {
        host = element(local.build_public_ips, count.index)
        type = "ssh"
    }
}

##NOTE: Uses ansible
##TODO: Figure out how best to organize modules/playbooks/hostfile
## NOTE: Kubernetes admin requires 2 cores and 2 GB of ram
module "kubernetes" {
    source = "../../modules/kubernetes"
    depends_on = [
        module.cloud,
        module.ansible,
        module.init,
        module.consul,
        module.cron,
        module.gpg,
        module.gitlab,
        module.nginx,
        module.clusterdb,
        module.docker,
        module.letsencrypt,
        module.cirunners,
        null_resource.install_unity
    ]

    ansible_hosts = local.ansible_hosts
    ansible_hostfile = local.ansible_hostfile
    predestroy_hostfile = local.predestroy_hostfile
    remote_state_hosts = local.remote_state_hosts

    admin_servers = local.admin_servers
    server_count = local.server_count

    gitlab_runner_tokens = local.gitlab_runner_tokens
    root_domain_name = local.root_domain_name
    import_gitlab = var.import_gitlab
    vpc_private_iface = local.vpc_private_iface
    active_env_provider = var.active_env_provider

    kubernetes_version = local.kubernetes_version
    buildkitd_version = var.buildkitd_version
    container_orchestrators = var.container_orchestrators
    cleanup_kube_volumes = local.cleanup_kube_volumes

    cloud_provider = local.cloud_provider
    cloud_provider_token = local.cloud_provider_token
    csi_namespace = local.csi_namespace
    csi_version = local.csi_version

    additional_ssl = var.additional_ssl
}

resource "null_resource" "configure_smtp" {
    count = local.admin_servers
    depends_on = [
        module.cloud,
        module.ansible,
        module.init,
        module.consul,
        module.cron,
        module.gpg,
        module.gitlab,
        module.nginx,
        module.clusterdb,
        module.docker,
        module.letsencrypt,
        module.cirunners,
        null_resource.install_unity,
        module.kubernetes,
    ]

    provisioner "file" {
        content = <<-EOF
            SENDGRID_KEY=${local.sendgrid_apikey}

            if [ -n "$SENDGRID_KEY" ]; then
                bash $HOME/code/scripts/misc/configureSMTP.sh -k ${local.sendgrid_apikey} -d ${local.sendgrid_domain};
            else
                bash $HOME/code/scripts/misc/configureSMTP.sh -d ${local.root_domain_name};
            fi
        EOF
        destination = "/tmp/configSMTP.sh"
    }
    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/configSMTP.sh",
            "bash /tmp/configSMTP.sh",
            "rm /tmp/configSMTP.sh"
        ]
    }

    connection {
        host = element(local.admin_public_ips, 0)
        type = "ssh"
    }
}

resource "null_resource" "enable_autoupgrade" {
    depends_on = [
        module.cloud,
        module.ansible,
        module.init,
        module.consul,
        module.cron,
        module.gpg,
        module.gitlab,
        module.nginx,
        module.clusterdb,
        module.docker,
        module.letsencrypt,
        module.cirunners,
        null_resource.install_unity,
        module.kubernetes,
        null_resource.configure_smtp,
    ]

    triggers = {
        num_hosts = local.server_count
        hostfile = local.ansible_hostfile
        predestroy_hostfile = local.predestroy_hostfile
    }

    provisioner "local-exec" {
        command = "ansible-playbook ../../modules/init/playbooks/end.yml -i ${local.ansible_hostfile}"
    }

    ## Copy old ansible file to preserve hosts before their destruction
    ## As this is destroyed first, best location to create the temp old hosts file
    provisioner "local-exec" {
        when = destroy
        command = "cp ${self.triggers.hostfile} ${self.triggers.predestroy_hostfile}"
    }
    ## Remove any pre-destroy hostfiles since this created last
    provisioner "local-exec" {
        command = "rm ${local.predestroy_hostfile} || echo"
    }
}


locals {
    ###! provider based
    vpc_private_iface = local.vpc_private_ifaces[var.active_env_provider]
    s3alias = local.s3aliases[local.active_s3_provider]
    s3bucket = local.s3buckets[local.active_s3_provider]
    region = local.regions[var.active_env_provider]
    cloud_provider = local.cloud_providers[var.active_env_provider]
    cloud_provider_token = local.cloud_provider_tokens[var.active_env_provider]
    csi_namespace = local.csi_namespaces[var.active_env_provider]
    csi_version = local.csi_versions[var.active_env_provider]
    vpc_private_ifaces = {
        "digital_ocean" = "eth1"
        "aws" = "ens5"
        "azure" = "eth0"
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
        # For kubernetes 1.20 use digitalocean csi 3.0.0
        # TODO: Correct csi version based on kubernetes version
        "digital_ocean" = "3.0.0"
        "aws" = ""
        "azure" = ""
    }

    ###! workspace based
    ansible_hostfile = "./${terraform.workspace}_ansible_hosts"
    predestroy_hostfile = "${local.ansible_hostfile}-predestroy"
    additional_domains = terraform.workspace == "default" ? var.additional_domains : {}

    ansible_hosts = module.cloud.ansible_hosts
    gitlab_runner_tokens = var.import_gitlab ? local.gitlab_runner_registration_tokens : {service = ""}

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
    kubernetes_version = var.kubernetes_version == "" ? "latest" : local.gitlab_kube_version
    cleanup_kube_volumes = terraform.workspace == "default" ? false : var.cleanup_kube_volumes

    remote_state_hosts = (lookup(data.terraform_remote_state.cloud.outputs, "hosts", null) != null
        ? data.terraform_remote_state.cloud.outputs.hosts : {})

    server_count = sum(tolist([ for SERVER in local.servers: SERVER.count ]))
    admin_servers = sum(concat([0], tolist([
        for SERVER in local.servers: SERVER.count
        if contains(SERVER.roles, "admin")
    ])))
    lead_servers = sum(concat([0], tolist([
        for SERVER in local.servers: SERVER.count
        if contains(SERVER.roles, "lead")
    ])))
    db_servers = sum(concat([0], tolist([
        for SERVER in local.servers: SERVER.count
        if contains(SERVER.roles, "db")
    ])))
    build_servers = sum(concat([0], tolist([
        for SERVER in local.servers: SERVER.count
        if contains(SERVER.roles, "build")
    ])))

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


    admin_public_ips = flatten([
        for role, hosts in module.cloud.ansible_hosts: [
            for HOST in hosts: HOST.ip
            if contains(HOST.roles, "admin")
        ]
    ])
    build_public_ips = flatten([
        for role, hosts in module.cloud.ansible_hosts: [
            for HOST in hosts: HOST.ip
            if contains(HOST.roles, "build")
        ]
    ])
}

locals {
    ##! local.config is a wrapper to pass into module.cloud in vars.tf
    config = {
        ## Machine/Misc
        servers = local.servers
        region = local.region
        server_name_prefix = local.server_name_prefix
        active_env_provider = var.active_env_provider
        local_ssh_key_file = var.local_ssh_key_file
        app_definitions = var.app_definitions
        packer_config = local.packer_config
        container_orchestrators = var.container_orchestrators
        managed_kubernetes_conf = contains(var.container_orchestrators, "managed_kubernetes") ? local.managed_kubernetes_conf : []

        ## DNS
        root_domain_name = local.root_domain_name
        additional_domains = local.additional_domains
        additional_ssl = var.additional_ssl
        admin_arecord_aliases = var.admin_arecord_aliases
        db_arecord_aliases = var.db_arecord_aliases
        leader_arecord_aliases = var.leader_arecord_aliases
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

        ## Credentials/Cloud
        do_token = var.do_token
        do_region = var.do_region
        do_ssh_fingerprint = var.do_ssh_fingerprint

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

        remote_state_hosts = (lookup(data.terraform_remote_state.cloud.outputs, "hosts", null) != null
            ? data.terraform_remote_state.cloud.outputs.hosts : {})
    }
}


####! TODO: Need to revisit cross DC communication at some point
####! NOTE: Below comments relate to older ideas regarding it

# TODO: Dynamically change if using multiple providers/modules
#external_leaderIP = (var.active_env_provider == "digital_ocean"
#    ? element(concat(module.main.lead_public_ip_addresses, [""]), 0)
#    : element(concat(module.main.lead_public_ip_addresses, [""]), 0))

# TODO: Review cross data center communication
# do_leaderIP
# aws_leaderIP = "${module.aws.aws_ip}"
