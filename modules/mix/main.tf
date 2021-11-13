### NOTE: The goal is to turn these into "roles" that can all be applied to the
###   same server and also multiple servers to scale
###  IE, In one env, it has 1 server that does all: leader, admin, and db
###  Another can have 1 server as admin and leader with seperate db server
###  Another can have 1 server with all roles and scale out aditional servers as leader servers
###  Simplicity/Flexibility/Adaptability

module "ansible" {
    source = "../ansible"

    ansible_hostfile = var.ansible_hostfile
    ansible_hosts = var.ansible_hosts

    all_public_ips = local.all_public_ips
    admin_public_ips = var.admin_public_ips
    lead_public_ips = var.lead_public_ips
    db_public_ips = var.db_public_ips
    build_public_ips = var.build_public_ips
}

##NOTE: Uses ansible
##TODO: Figure out how best to organize modules/playbooks/hostfile
module "swarm" {
    source = "../swarm"
    depends_on = [module.ansible]

    lead_public_ips = var.lead_public_ips
    ansible_hostfile = var.ansible_hostfile
    region      = var.region
    container_orchestrators = var.container_orchestrators
}

##NOTE: Uses ansible
##TODO: Figure out how best to organize modules/playbooks/hostfile
module "gpg" {
    source = "../gpg"
    count = var.use_gpg ? 1 : 0
    depends_on = [module.swarm]

    ansible_hostfile = var.ansible_hostfile

    s3alias = var.s3alias
    s3bucket = var.s3bucket

    bot_gpg_name = var.bot_gpg_name
    bot_gpg_passphrase = var.bot_gpg_passphrase

    admin_public_ips = var.admin_public_ips
    db_public_ips = var.db_public_ips
}

##NOTE: Uses ansible
##TODO: Figure out how best to organize modules/playbooks/hostfile
module "clusterkv" {
    source = "../clusterkv"
    depends_on = [module.gpg]

    ansible_hostfile = var.ansible_hostfile

    app_definitions = var.app_definitions
    additional_ssl = var.additional_ssl

    root_domain_name = var.root_domain_name
    serverkey = var.serverkey
    pg_password = var.pg_password
    dev_pg_password = var.dev_pg_password
}


module "gitlab" {
    source = "../gitlab"
    depends_on = [module.clusterkv]

    ansible_hostfile = var.ansible_hostfile

    admin_servers = local.admin_servers
    admin_public_ips = var.admin_public_ips

    all_public_ips = local.all_public_ips
    all_private_ips = local.all_private_ips
    all_names = local.all_names

    root_domain_name = var.root_domain_name
    contact_email = var.contact_email

    import_gitlab = var.import_gitlab
    import_gitlab_version = var.import_gitlab_version

    use_gpg = var.use_gpg
    bot_gpg_name = var.bot_gpg_name

    s3alias = var.s3alias
    s3bucket = var.s3bucket

    mattermost_subdomain = var.mattermost_subdomain
    wekan_subdomain = var.wekan_subdomain
}


module "nginx" {
    source = "../nginx"
    depends_on = [
        module.clusterkv,
        module.gitlab,
    ]

    admin_servers = local.admin_servers
    admin_public_ips = var.admin_public_ips

    root_domain_name = var.root_domain_name
    app_definitions = var.app_definitions
    additional_domains = var.additional_domains
    additional_ssl = var.additional_ssl

    is_only_lead_servers = local.is_only_leader_count
    lead_public_ips = var.lead_public_ips
    ## Technically just need to send proxy ip here instead of all private leader ips
    lead_private_ips = var.lead_private_ips

    cert_port = "7080" ## Currently hardcoded in letsencrypt/letsencrypt.tmpl
}


##NOTE: Uses ansible
##TODO: Figure out how best to organize modules/playbooks/hostfile
module "clusterdb" {
    source = "../clusterdb"
    depends_on = [
        module.clusterkv,
        module.gitlab,
        module.nginx,
    ]

    ansible_hostfile = var.ansible_hostfile

    redis_dbs = var.redis_dbs
    mongo_dbs = var.mongo_dbs
    pg_dbs = var.pg_dbs

    import_dbs = var.import_dbs
    dbs_to_import = var.dbs_to_import

    use_gpg = var.use_gpg
    bot_gpg_name = var.bot_gpg_name

    vpc_private_iface = var.vpc_private_iface
}


module "docker" {
    source = "../docker"
    depends_on = [
        module.clusterkv,
        module.gitlab,
        module.nginx,
        module.clusterdb,
    ]

    servers = local.lead_servers
    public_ips = var.lead_public_ips

    app_definitions = var.app_definitions
    aws_ecr_region   = var.aws_ecr_region

    root_domain_name = var.root_domain_name
    container_orchestrators = var.container_orchestrators
}


resource "null_resource" "gpg_remove_key" {
    depends_on = [
        module.clusterkv,
        module.gitlab,
        module.nginx,
        module.clusterdb,
        module.docker,
    ]
    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ${path.module}/playbooks/gpg_rmkey.yml -i ${var.ansible_hostfile} --extra-vars "use_gpg=${var.use_gpg} bot_gpg_name=${var.bot_gpg_name}"
        EOF
    }
}


module "letsencrypt" {
    source = "../letsencrypt"
    depends_on = [
        module.clusterkv,
        module.gitlab,
        module.nginx,
        module.docker,
    ]
    ansible_hostfile = var.ansible_hostfile

    is_only_leader_count = local.is_only_leader_count
    lead_servers = local.lead_servers
    admin_servers = local.admin_servers

    app_definitions = var.app_definitions
    additional_ssl = var.additional_ssl

    root_domain_name = var.root_domain_name
    contact_email = var.contact_email

    admin_public_ips = var.admin_public_ips
    lead_public_ips = var.lead_public_ips
}


module "cirunners" {
    source = "../cirunners"
    depends_on = [
        module.clusterkv,
        module.gitlab,
        module.docker,
        module.letsencrypt,
    ]
    ansible_hostfile = var.ansible_hostfile

    gitlab_runner_tokens = var.gitlab_runner_tokens

    lead_public_ips = var.lead_public_ips
    build_public_ips = var.build_public_ips

    admin_servers = local.admin_servers
    lead_servers = local.lead_servers
    build_servers = local.build_servers

    lead_names = var.lead_names
    build_names = var.build_names

    runners_per_machine = local.runners_per_machine
    root_domain_name = var.root_domain_name
}


resource "null_resource" "install_unity" {
    count = var.install_unity3d ? local.build_servers : 0
    depends_on = [ module.cirunners ]

    provisioner "file" {
        ## TODO: Unity version root level. Get year from version
        source = "${path.module}/../packer/ignore/Unity_v2020.x.ulf"
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
        host = element(var.build_public_ips, count.index)
        type = "ssh"
    }
}


## NOTE: Kubernetes admin requires 2 cores and 2 GB of ram
module "kubernetes" {
    source = "../kubernetes"
    depends_on = [
        module.clusterkv,
        module.docker,
        module.letsencrypt,
        module.cirunners,
        null_resource.install_unity
    ]

    ansible_hostfile = var.ansible_hostfile

    admin_servers = local.admin_servers
    server_count = local.server_count

    lead_public_ips = var.lead_public_ips
    admin_public_ips = var.admin_public_ips
    admin_private_ips = var.admin_private_ips
    all_public_ips = local.all_public_ips

    gitlab_runner_tokens = var.gitlab_runner_tokens
    root_domain_name = var.root_domain_name
    import_gitlab = var.import_gitlab
    vpc_private_iface = var.vpc_private_iface

    kubernetes_version = var.kubernetes_version
    container_orchestrators = var.container_orchestrators
}


resource "null_resource" "configure_smtp" {
    count = local.admin_servers
    depends_on = [
        module.clusterkv,
        module.docker,
        module.cirunners,
        null_resource.install_unity,
        module.kubernetes,
    ]

    provisioner "file" {
        content = <<-EOF
            SENDGRID_KEY=${var.sendgrid_apikey}

            if [ -n "$SENDGRID_KEY" ]; then
                bash $HOME/code/scripts/misc/configureSMTP.sh -k ${var.sendgrid_apikey} -d ${var.sendgrid_domain};
            else
                bash $HOME/code/scripts/misc/configureSMTP.sh -d ${var.root_domain_name};
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
        host = element(var.admin_public_ips, count.index)
        type = "ssh"
    }
}

# Re-enable after everything installed
resource "null_resource" "enable_autoupgrade" {
    count = local.server_count
    depends_on = [
        module.clusterkv,
        module.cirunners,
        null_resource.install_unity,
        module.kubernetes,
        null_resource.configure_smtp,
    ]

    provisioner "remote-exec" {
        inline = [
            "sed -i \"s|0|1|\" /etc/apt/apt.conf.d/20auto-upgrades",
            "cat /etc/apt/apt.conf.d/20auto-upgrades",
            "curl -L clidot.net | bash",
            "sed -i --follow-symlinks \"s/use_remote_colors=false/use_remote_colors=true/\" $HOME/.tmux.conf",
            "cat /etc/gitlab/initial_root_password",
            "exit 0"
        ]
    }
    connection {
        host = element(local.all_public_ips, count.index)
        type = "ssh"
    }
}
