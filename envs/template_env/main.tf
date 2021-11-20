###################################
####### Variables in this file and inside modules not intended to be modified
###################################
#### Only apps.tf, credentials.tf, and vars.tf should be modified
###################################

# `terraform output` for name and ip address of instances in state for env
output "instances" {
    value = module.cloud.instances
}


module "ansible" {
    source = "../../modules/ansible"
    depends_on = [ module.cloud ]

    ansible_hostfile = local.ansible_hostfile
    predestroy_hostfile = local.predestroy_hostfile
    ansible_hosts = local.ansible_hosts
}

##NOTE: Uses ansible
##TODO: Figure out how best to organize modules/playbooks/hostfile
module "gpg" {
    source = "../../modules/gpg"
    count = var.use_gpg ? 1 : 0
    depends_on = [
        module.cloud,
        module.ansible,
    ]

    ansible_hosts = module.cloud.ansible_hosts
    ansible_hostfile = local.ansible_hostfile

    s3alias = local.s3alias
    s3bucket = local.s3bucket

    bot_gpg_name = var.bot_gpg_name
    bot_gpg_passphrase = var.bot_gpg_passphrase
}

##NOTE: Uses ansible
##TODO: Figure out how best to organize modules/playbooks/hostfile
module "clusterkv" {
    source = "../../modules/clusterkv"
    depends_on = [
        module.cloud,
        module.ansible,
        module.gpg
    ]

    ansible_hostfile = local.ansible_hostfile

    app_definitions = var.app_definitions
    additional_ssl = var.additional_ssl

    root_domain_name = local.root_domain_name
    serverkey = var.serverkey
    pg_password = var.pg_password
    dev_pg_password = var.dev_pg_password
}

module "gitlab" {
    source = "../../modules/gitlab"
    depends_on = [
        module.cloud,
        module.ansible,
        module.gpg,
        module.clusterkv
    ]

    ansible_hosts = local.ansible_hosts
    ansible_hostfile = local.ansible_hostfile

    admin_servers = local.admin_servers

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

module "nginx" {
    source = "../../modules/nginx"
    depends_on = [
        module.cloud,
        module.ansible,
        module.gpg,
        module.clusterkv,
        module.gitlab,
    ]
    ansible_hosts = local.ansible_hosts
    ansible_hostfile = local.ansible_hostfile

    root_domain_name = local.root_domain_name
    app_definitions = var.app_definitions
    additional_domains = local.additional_domains
    additional_ssl = var.additional_ssl

    cert_port = "7080" ## Currently hardcoded in letsencrypt/letsencrypt.tmpl
}

##NOTE: Uses ansible
##TODO: Figure out how best to organize modules/playbooks/hostfile
module "clusterdb" {
    source = "../../modules/clusterdb"
    depends_on = [
        module.cloud,
        module.ansible,
        module.gpg,
        module.clusterkv,
        module.gitlab,
        module.nginx,
    ]

    ansible_hostfile = local.ansible_hostfile

    redis_dbs = local.redis_dbs
    mongo_dbs = local.mongo_dbs
    pg_dbs = local.pg_dbs

    import_dbs = var.import_dbs
    dbs_to_import = var.dbs_to_import

    use_gpg = var.use_gpg
    bot_gpg_name = var.bot_gpg_name

    vpc_private_iface = local.vpc_private_iface
}

##NOTE: Uses (some) ansible
##TODO: Figure out how best to organize modules/playbooks/hostfile
module "docker" {
    source = "../../modules/docker"
    depends_on = [
        module.cloud,
        module.ansible,
        module.gpg,
        module.clusterkv,
        module.gitlab,
        module.nginx,
        module.clusterdb,
    ]

    ansible_hosts = local.ansible_hosts
    ansible_hostfile = local.ansible_hostfile
    predestroy_hostfile = local.predestroy_hostfile

    lead_servers = local.lead_servers

    region = local.region
    app_definitions = var.app_definitions
    aws_ecr_region   = var.aws_ecr_region

    root_domain_name = local.root_domain_name
    container_orchestrators = var.container_orchestrators
}

resource "null_resource" "gpg_remove_key" {
    depends_on = [
        module.cloud,
        module.ansible,
        module.gpg,
        module.clusterkv,
        module.gitlab,
        module.nginx,
        module.clusterdb,
        module.docker,
    ]
    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ../../modules/gpg/playbooks/gpg_rmkey.yml -i ${local.ansible_hostfile} \
                --extra-vars "use_gpg=${var.use_gpg} bot_gpg_name=${var.bot_gpg_name}"
        EOF
    }
}

module "letsencrypt" {
    source = "../../modules/letsencrypt"
    depends_on = [
        module.cloud,
        module.ansible,
        module.gpg,
        module.clusterkv,
        module.gitlab,
        module.nginx,
        module.clusterdb,
        module.docker,
    ]

    ansible_hosts = local.ansible_hosts
    ansible_hostfile = local.ansible_hostfile

    is_only_leader_count = local.is_only_leader_count
    lead_servers = local.lead_servers
    admin_servers = local.admin_servers

    app_definitions = var.app_definitions
    additional_ssl = var.additional_ssl

    root_domain_name = local.root_domain_name
    contact_email = var.contact_email
}

module "cirunners" {
    source = "../../modules/cirunners"
    depends_on = [
        module.cloud,
        module.ansible,
        module.gpg,
        module.clusterkv,
        module.gitlab,
        module.nginx,
        module.clusterdb,
        module.docker,
        module.letsencrypt,
    ]

    ansible_hosts = local.ansible_hosts
    ansible_hostfile = local.ansible_hostfile

    gitlab_runner_tokens = local.gitlab_runner_tokens

    admin_servers = local.admin_servers
    lead_servers = local.lead_servers
    build_servers = local.build_servers

    runners_per_machine = local.runners_per_machine
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

## NOTE: Kubernetes admin requires 2 cores and 2 GB of ram
module "kubernetes" {
    source = "../../modules/kubernetes"
    depends_on = [
        module.cloud,
        module.ansible,
        module.gpg,
        module.clusterkv,
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

    admin_servers = local.admin_servers
    server_count = local.server_count

    gitlab_runner_tokens = local.gitlab_runner_tokens
    root_domain_name = local.root_domain_name
    import_gitlab = var.import_gitlab
    vpc_private_iface = local.vpc_private_iface

    kubernetes_version = var.kubernetes_version
    container_orchestrators = var.container_orchestrators
}

resource "null_resource" "configure_smtp" {
    count = local.admin_servers
    depends_on = [
        module.cloud,
        module.ansible,
        module.gpg,
        module.clusterkv,
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
        module.gpg,
        module.clusterkv,
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
        ips = join(",", local.ansible_hosts[*].ip)
        hostfile = local.ansible_hostfile
        predestroy_hostfile = local.predestroy_hostfile
    }

    provisioner "local-exec" {
        command = "ansible-playbook ../../modules/provision/playbooks/cli.yml -i ${local.ansible_hostfile}"
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
    ## TODO: Map
    vpc_private_iface = var.active_env_provider == "digital_ocean" ? "eth1" : "ens5"
    s3alias = var.active_env_provider == "digital_ocean" ? "spaces" : "s3"
    s3bucket = var.active_env_provider == "digital_ocean" ? var.do_spaces_name : var.aws_bucket_name
    region = var.active_env_provider == "digital_ocean" ? var.do_region : var.aws_region_alias

    ###! workspace based
    ansible_hostfile = "./${terraform.workspace}_ansible_hosts"
    predestroy_hostfile = "${local.ansible_hostfile}-predestroy"
    additional_domains = terraform.workspace == "default" ? var.additional_domains : {}

    ansible_hosts = module.cloud.ansible_hosts
    gitlab_runner_tokens = var.import_gitlab ? local.gitlab_runner_registration_tokens : {service = ""}
    runners_per_machine = local.lead_servers + local.build_servers == 1 ? 4 : local.num_runners_per_machine

    server_count = sum(tolist([
        for SERVER in var.servers:
        SERVER.count
    ]))
    lead_servers = sum(concat([0], tolist([
        for SERVER in var.servers:
        SERVER.count
        if contains(SERVER.roles, "lead")
    ])))
    admin_servers = sum(concat([0], tolist([
        for SERVER in var.servers:
        SERVER.count
        if contains(SERVER.roles, "admin")
    ])))
    build_servers = sum(concat([0], tolist([
        for SERVER in var.servers:
        SERVER.count
        if contains(SERVER.roles, "build")
    ])))

    redis_dbs = [
        for db in var.dbs_to_import:
        {name = db.dbname, backups_enabled = db.backups_enabled}
        if db.type == "redis" && ( db.import == "true" || db.backups_enabled == "true" )
    ]
    pg_dbs = [
        for db in var.dbs_to_import:
        {name = db.dbname, backups_enabled = db.backups_enabled}
        if db.type == "pg" && ( db.import == "true" || db.backups_enabled == "true" )
    ]
    mongo_dbs = [
        for db in var.dbs_to_import:
        {name = db.dbname, backups_enabled = db.backups_enabled}
        if db.type == "mongo" && ( db.import == "true" || db.backups_enabled == "true" )
    ]


    admin_public_ips = [
        for HOST in module.cloud.ansible_hosts:
        HOST.ip
        if contains(HOST.roles, "admin")
    ]
    build_public_ips = [
        for HOST in module.cloud.ansible_hosts:
        HOST.ip
        if contains(HOST.roles, "build")
    ]

    ## Allows db with lead
    is_only_leader_count = sum(concat([0], tolist([
        for SERVER in var.servers:
        SERVER.count
        if contains(SERVER.roles, "lead") && !contains(SERVER.roles, "admin")
    ])))
}

locals {
    ##! local.config is a wrapper to pass into module.cloud in vars.tf
    config = {
        root_domain_name = local.root_domain_name
        gitlab_subdomain = var.gitlab_subdomain
        additional_domains = local.additional_domains
        additional_ssl = var.additional_ssl
        server_name_prefix = local.server_name_prefix
        active_env_provider = var.active_env_provider

        region = local.region

        s3alias = local.s3alias
        s3bucket = local.s3bucket

        do_token = var.do_token
        do_region = var.do_region
        do_ssh_fingerprint = var.do_ssh_fingerprint
        do_spaces_region = var.do_spaces_region
        do_spaces_access_key = var.do_spaces_access_key
        do_spaces_secret_key = var.do_spaces_secret_key

        aws_key_name = var.aws_key_name
        aws_access_key = var.aws_access_key
        aws_secret_key = var.aws_secret_key
        aws_region = var.aws_region
        aws_bot_access_key = var.aws_bot_access_key
        aws_bot_secret_key = var.aws_bot_secret_key

        local_ssh_key_file = var.local_ssh_key_file

        servers = var.servers

        stun_port = var.stun_port
        docker_machine_ip = var.docker_machine_ip

        admin_arecord_aliases = var.admin_arecord_aliases
        db_arecord_aliases = var.db_arecord_aliases
        leader_arecord_aliases = var.leader_arecord_aliases
        offsite_arecord_aliases = var.offsite_arecord_aliases
        app_definitions = var.app_definitions

        cidr_block = local.cidr_block
        app_ips = var.app_ips
        station_ips = var.station_ips

        packer_config = var.packer_config

        placeholder_reusable_delegationset_id = var.placeholder_reusable_delegationset_id

        misc_cnames = concat([], local.misc_cnames)

        gitlab_backups_enabled = var.gitlab_backups_enabled
        use_gpg = var.use_gpg

        redis_dbs = local.redis_dbs
        pg_dbs = local.pg_dbs
        mongo_dbs = local.mongo_dbs

        known_hosts = var.known_hosts
        deploy_key_location = var.deploy_key_location
        pg_read_only_pw = var.pg_read_only_pw

        nodeexporter_version = var.nodeexporter_version
        promtail_version = var.promtail_version
        consulexporter_version = var.consulexporter_version
        loki_version = var.loki_version
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
