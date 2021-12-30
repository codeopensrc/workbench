variable "ansible_hosts" {}
variable "ansible_hostfile" {}
variable "predestroy_hostfile" {}
variable "remote_state_hosts" {}

variable "db_servers" {}

variable "redis_dbs" {}
variable "mongo_dbs" {}
variable "pg_dbs" {}

variable "import_dbs" {}
variable "dbs_to_import" {}
variable "use_gpg" {}
variable "bot_gpg_name" {}

variable "root_domain_name" {}

locals {
    db_public_ips = flatten([
        for role, hosts in var.ansible_hosts: [
            for HOST in hosts: HOST.ip
            if contains(HOST.roles, "db")
        ]
    ])
    old_db_public_ips = flatten([
        for role, hosts in var.remote_state_hosts: [
            for HOST in hosts: HOST.ip
            if contains(HOST.roles, "db")
        ]
    ])
}

resource "null_resource" "configure_dbs" {
    triggers = {
        install_redis = length(var.redis_dbs) > 0 ? true : false
        install_mongo = length(var.mongo_dbs) > 0 ? true : false
        install_pg = length(var.pg_dbs) > 0 ? true : false
        num_db = var.db_servers
        total_dbs = sum([length(var.pg_dbs), length(var.redis_dbs), length(var.mongo_dbs)])
    }
    ## Run playbook with old ansible file and new names to find out the ones to be deleted, drain and removing them
    provisioner "local-exec" {
        command = <<-EOF
            if [ ${length(local.db_public_ips)} -lt ${length(local.old_db_public_ips)} ]; then
                if [ -f "${var.predestroy_hostfile}" ]; then
                    ansible-playbook ${path.module}/playbooks/clusterdb_rm.yml -i ${var.predestroy_hostfile} \
                        --extra-vars 'db_public_ips=${jsonencode(local.db_public_ips)}';
                    
                fi
            fi
        EOF
    }

    ##TODO: Split install vs import
    provisioner "local-exec" {
        command = <<-EOF
            if [ ${length(local.db_public_ips)} -ge ${length(local.old_db_public_ips)} ]; then
                ansible-playbook ${path.module}/playbooks/clusterdb.yml -i ${var.ansible_hostfile} --extra-vars \
                    'redis_dbs=${jsonencode(var.redis_dbs)}
                    mongo_dbs=${jsonencode(var.mongo_dbs)}
                    pg_dbs=${jsonencode(var.pg_dbs)}
                    dbs_to_import=${jsonencode(var.dbs_to_import)}
                    import_dbs=${var.import_dbs}
                    use_gpg=${var.use_gpg}
                    root_domain_name=${var.root_domain_name}
                    bot_gpg_name=${var.bot_gpg_name}'
            fi
        EOF
    }
}
