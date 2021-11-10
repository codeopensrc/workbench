variable "redis_dbs" {}
variable "mongo_dbs" {}
variable "pg_dbs" {}

variable "import_dbs" {}
variable "dbs_to_import" {}
variable "use_gpg" {}
variable "bot_gpg_name" {}

variable "vpc_private_iface" {}
variable "db_public_ips" {}

variable "ansible_hostfile" { default = "" }

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

    #provisioner "remote-exec" {
    #    # TODO: Setup to bind to private net/vpc instead of relying soley on the security group/firewall for all dbs
    #    inline = [
    #        "chmod +x /root/code/scripts/install/install_redis.sh",
    #        "chmod +x /root/code/scripts/install/install_mongo.sh",
    #        "chmod +x /root/code/scripts/install/install_pg.sh",
    #        (length(var.redis_dbs) > 0 ? "sudo service redis_6379 start;" : "echo 0;"),
    #        (length(var.redis_dbs) > 0 ? "sudo systemctl enable redis_6379" : "echo 0;"),
    #        (length(var.mongo_dbs) > 0
    #            ? "bash /root/code/scripts/install/install_mongo.sh -v 4.4.6 -i ${element(var.db_private_ips, count.index)};"
    #            : "echo 0;"),
    #        (length(var.pg_dbs) > 0
    #            ? "bash /root/code/scripts/install/install_pg.sh -v 9.5;"
    #            : "echo 0;"),
    #        "exit 0;"
    #    ]
    #}
    #connection {
    #    host = element(var.db_public_ips, count.index)
    #    type = "ssh"
    #}
}

#resource "null_resource" "import_dbs" {
#    #count = var.import_dbs && local.db_servers > 0 ? length(var.dbs_to_import) : 0
#    count = var.import_dbs ? length(var.dbs_to_import) : 0
#    depends_on = [
#        null_resource.install_dbs
#    ]
#
#    provisioner "file" {
#        content = <<-EOF
#            IMPORT=${var.dbs_to_import[count.index]["import"]};
#            DB_TYPE=${var.dbs_to_import[count.index]["type"]};
#            S3_BUCKET_NAME=${var.dbs_to_import[count.index]["s3bucket"]};
#            S3_ALIAS=${var.dbs_to_import[count.index]["s3alias"]};
#            DB_NAME=${var.dbs_to_import[count.index]["dbname"]};
#            HOST=${element(var.db_private_ips, count.index)}
#            PASSPHRASE_FILE="${var.use_gpg ? "-p $HOME/${var.bot_gpg_name}" : "" }"
#
#            if [ "$IMPORT" = "true" ] && [ "$DB_TYPE" = "mongo" ]; then
#                bash /root/code/scripts/db/import_mongo_db.sh -a $S3_ALIAS -b $S3_BUCKET_NAME -d $DB_NAME -h $HOST $PASSPHRASE_FILE;
#                cp /etc/consul.d/templates/mongo.json /etc/consul.d/conf.d/mongo.json
#            fi
#
#            if [ "$IMPORT" = "true" ] && [ "$DB_TYPE" = "pg" ]; then
#                bash /root/code/scripts/db/import_pg_db.sh -a $S3_ALIAS -b $S3_BUCKET_NAME -d $DB_NAME $PASSPHRASE_FILE;
#                cp /etc/consul.d/templates/pg.json /etc/consul.d/conf.d/pg.json
#            fi
#
#            if [ "$IMPORT" = "true" ] && [ "$DB_TYPE" = "redis" ]; then
#                bash /root/code/scripts/db/import_redis_db.sh -a $S3_ALIAS -b $S3_BUCKET_NAME -d $DB_NAME $PASSPHRASE_FILE;
#                cp /etc/consul.d/templates/redis.json /etc/consul.d/conf.d/redis.json
#            fi
#        EOF
#        destination = "/tmp/import_dbs-${count.index}.sh"
#    }
#
#    provisioner "remote-exec" {
#        inline = [
#            "chmod +x /tmp/import_dbs-${count.index}.sh",
#            "/tmp/import_dbs-${count.index}.sh"
#        ]
#    }
#
#    connection {
#        # TODO: Determine how to handle multiple db servers
#        host = element(var.db_public_ips, 0)
#        type = "ssh"
#    }
#}
#
#
resource "null_resource" "db_ready" {
    depends_on = [null_resource.configure_dbs]

    provisioner "file" {
        content = <<-EOF
            check_consul() {
                SET_BOOTSTRAPPED=$(consul kv get init/db_bootstrapped);

                if [ "$SET_BOOTSTRAPPED" = "true" ]; then
                    echo "Set DB bootstrapped";
                    exit 0;
                else
                    echo "Waiting 10 for consul";
                    sleep 10;
                    consul reload;
                    consul kv put init/db_bootstrapped true
                    check_consul
                fi
            }

            check_consul
        EOF
        destination = "/tmp/set_db_bootstrapped.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/set_db_bootstrapped.sh",
            "bash /tmp/set_db_bootstrapped.sh",
        ]
    }

    connection {
        host = element(var.db_public_ips, 0)
        type = "ssh"
    }
}
