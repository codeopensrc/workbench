variable "ansible_hostfile" { default = "" }

variable "redis_dbs" {}
variable "mongo_dbs" {}
variable "pg_dbs" {}

variable "import_dbs" {}
variable "dbs_to_import" {}
variable "use_gpg" {}
variable "bot_gpg_name" {}

variable "vpc_private_iface" {}


resource "null_resource" "configure_dbs" {
    triggers = {
        install_redis = length(var.redis_dbs) > 0 ? true : false
        install_mongo = length(var.mongo_dbs) > 0 ? true : false
        install_pg = length(var.pg_dbs) > 0 ? true : false
    }

    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ${path.module}/playbooks/clusterdb.yml -i ${var.ansible_hostfile} --extra-vars \
                'redis_dbs=${jsonencode(var.redis_dbs)}
                mongo_dbs=${jsonencode(var.mongo_dbs)}
                pg_dbs=${jsonencode(var.pg_dbs)}
                dbs_to_import=${jsonencode(var.dbs_to_import)}
                import_dbs=${var.import_dbs}
                use_gpg=${var.use_gpg}
                bot_gpg_name=${var.bot_gpg_name}
                vpc_private_iface=${var.vpc_private_iface}'
        EOF
    }
}
