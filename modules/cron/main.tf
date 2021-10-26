
# All
variable "public_ip" { default = "" }
variable "roles" { default = [] }
variable "s3alias" { default = "" }
variable "s3bucket" { default = "" }
variable "use_gpg" { default = false }

variable "templates" {
    default = {
        admin = "admin.tmpl"
        leader = "leader.tmpl"
        app = "app.tmpl"
        redisdb = "redisdb.tmpl"
        mongodb = "mongodb.tmpl"
        pgdb = "pgdb.tmpl"
    }
}
variable "destinations" {
    default = {
        admin = "/root/code/cron/admin.cron"
        leader = "/root/code/cron/leader.cron"
        app = "/root/code/cron/app.cron"
        redisdb = "/root/code/cron/redisdb.cron"
        mongodb = "/root/code/cron/mongodb.cron"
        pgdb = "/root/code/cron/pgdb.cron"
    }
}

#Admin
variable "gitlab_backups_enabled" { default = false }

#DB
variable "redis_dbs" { default = [] }
variable "mongo_dbs" { default = [] }
variable "pg_dbs" { default = [] }

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
}



resource "null_resource" "admin" {
    count = contains(var.roles, "admin") ? 1 : 0

    provisioner "remote-exec" {
        inline = [ "mkdir -p /root/code/cron", ]
    }

    provisioner "file" {
        content = fileexists("${path.module}/templates/${var.templates["admin"]}") ? templatefile("${path.module}/templates/${var.templates["admin"]}", {
            gitlab_backups_enabled = var.gitlab_backups_enabled && local.allow_cron_backups
            s3alias = var.s3alias
            s3bucket = var.s3bucket
            use_gpg = var.use_gpg
        }) : ""
        destination = var.destinations["admin"]
    }

    connection {
        host = var.public_ip
        type = "ssh"
    }
}


# TODO: Create a scaleable resource for multiple dbs then create separate resource to combine
#  the files into a single crontab (this can be said for this entire module as illustrated
#  by their similarities, but for now 1 module with several specific resources. Steps)
resource "null_resource" "db" {
    count = contains(var.roles, "db") ? 1 : 0

    triggers = {
        num_dbs = sum([length(var.redis_dbs), length(var.mongo_dbs), length(var.pg_dbs)])
    }

    provisioner "remote-exec" {
        inline = [ "mkdir -p /root/code/cron" ]
    }

    provisioner "file" {
        content = fileexists("${path.module}/templates/${var.templates["redisdb"]}") ? templatefile("${path.module}/templates/${var.templates["redisdb"]}", {
            s3alias = var.s3alias
            s3bucket = var.s3bucket
            redis_dbs = length(var.redis_dbs) > 0 ? var.redis_dbs : []
            allow_cron_backups = local.allow_cron_backups
            use_gpg = var.use_gpg
        }) : ""
        destination = var.destinations["redisdb"]
    }

    provisioner "file" {
        content = fileexists("${path.module}/templates/${var.templates["mongodb"]}") ? templatefile("${path.module}/templates/${var.templates["mongodb"]}", {
            s3alias = var.s3alias
            s3bucket = var.s3bucket
            mongo_dbs = length(var.mongo_dbs) > 0 ? var.mongo_dbs : []
            host = "vpc.my_private_ip"  # TODO: Add ability to specific host/hostnames/ip
            allow_cron_backups = local.allow_cron_backups
            use_gpg = var.use_gpg
        }) : ""
        destination = var.destinations["mongodb"]
    }

    provisioner "file" {
        content = fileexists("${path.module}/templates/${var.templates["pgdb"]}") ? templatefile("${path.module}/templates/${var.templates["pgdb"]}", {
            s3alias = var.s3alias
            s3bucket = var.s3bucket
            pg_dbs = length(var.pg_dbs) > 0 ? var.pg_dbs : []
            allow_cron_backups = local.allow_cron_backups
            use_gpg = var.use_gpg
        }) : ""
        destination = var.destinations["pgdb"]
    }

    connection {
        host = var.public_ip
        type = "ssh"
    }
}



resource "null_resource" "leader" {
    count = contains(var.roles, "lead") ? 1 : 0

    provisioner "remote-exec" {
        inline = [ "mkdir -p /root/code/cron" ]
    }

    provisioner "file" {
        content = fileexists("${path.module}/templates/${var.templates["leader"]}") ? templatefile("${path.module}/templates/${var.templates["leader"]}", {
            check_ssl = count.index == 0 ? true : false
        }) : ""
        destination = var.destinations["leader"]
    }

    provisioner "file" {
        content = fileexists("${path.module}/templates/${var.templates["app"]}") ? templatefile("${path.module}/templates/${var.templates["app"]}", {
            app_definitions = [
                for APP in var.app_definitions:
                {   custom_backup_file = APP.custom_backup_file, repo_name = APP.repo_name,
                    backup_frequency = APP.backup_frequency, use_custom_backup = APP.use_custom_backup   }
                if APP.custom_backup_file != ""
            ]
            s3alias = var.s3alias
            s3bucket = var.s3bucket
            allow_cron_backups = local.allow_cron_backups
        }) : ""
        destination = var.destinations["app"]
    }

    connection {
        host = var.public_ip
        type = "ssh"
    }
}


resource "null_resource" "cron_exec" {
    count = contains(var.roles, "admin") || contains(var.roles, "lead") || contains(var.roles, "db") ? 1 : 0

    triggers = {
        # TODO: Only trigger update on certain servers
        crontab_upd = join(",", concat(null_resource.admin.*.id, null_resource.db.*.id, null_resource.leader.*.id))
    }

    depends_on = [
        null_resource.admin,
        null_resource.db,
        null_resource.leader,
    ]

    provisioner "remote-exec" {
        inline = [
            "cat /root/code/cron/*.cron > /root/code/cron/all.cron",
            "crontab /root/code/cron/all.cron",
            "crontab -l"
        ]
    }

    connection {
        host = var.public_ip
        type = "ssh"
    }
}
