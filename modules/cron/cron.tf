variable "ansible_hostfile" {}
# All
variable "lead_servers" {}
variable "admin_servers" {}
variable "db_servers" {}
variable "s3alias" { default = "" }
variable "s3bucket" { default = "" }
variable "use_gpg" { default = false }
#Admin
variable "gitlab_backups_enabled" { default = false }
#DB
variable "redis_dbs" { default = [] }
variable "mongo_dbs" { default = [] }
variable "pg_dbs" { default = [] }
variable "mongo_host" { default = "" }

#Leader
variable "app_definitions" {
    type = map(object({ pull=string, stable_version=string, use_stable=string,
        repo_url=string, repo_name=string, docker_registry=string, docker_registry_image=string,
        docker_registry_url=string, docker_registry_user=string, docker_registry_pw=string, service_name=string,
        green_service=string, blue_service=string, default_active=string, subdomain_name=string,
        use_custom_backup=string, custom_backup_file=string, backup_frequency=string
    }))
}

locals {
    allow_cron_backups = terraform.workspace == "default"
    mongo_host = var.mongo_host == "" ? "vpc.my_private_ip" : var.mongo_host
}


resource "null_resource" "cronjobs" {
    triggers = {
        num_apps = length(keys(var.app_definitions))
        lead_servers = var.lead_servers
        admin_servers = var.admin_servers
        db_servers = var.db_servers
        num_dbs = sum([length(var.redis_dbs), length(var.mongo_dbs), length(var.pg_dbs)])
    }

    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ${path.module}/playbooks/cron.yml -i ${var.ansible_hostfile} --extra-vars \
                'gitlab_backups_enabled=${var.gitlab_backups_enabled && local.allow_cron_backups}
                mongo_host=${local.mongo_host}
                redis_dbs_json=${jsonencode(length(var.redis_dbs) > 0 ? var.redis_dbs : [])}
                mongo_dbs_json=${jsonencode(length(var.mongo_dbs) > 0 ? var.mongo_dbs : [])}
                pg_dbs_json=${jsonencode(length(var.pg_dbs) > 0 ? var.pg_dbs : [])}
                s3alias=${var.s3alias}
                s3bucket=${var.s3bucket}
                use_gpg=${var.use_gpg}
                allow_cron_backups=${local.allow_cron_backups}
                app_definitions_json=${jsonencode([
                    for APP in var.app_definitions: APP  
                    if APP.custom_backup_file != ""
                ])}'

        EOF
    }
}
