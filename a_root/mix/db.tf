### NOTE: The goal is to turn these into "roles" that can all be applied to the
###   same server and also multiple servers to scale
###  IE, In one env, it has 1 server that does all: leader, admin, and db
###  Another can have 1 server as admin and leader with seperate db server
###  Another can have 1 server with all roles and scale out aditional servers as leader servers
###  Simplicity/Flexibility/Adaptability
module "db_provisioners" {
    source      = "./modules/misc"
    servers     = var.db_servers
    names       = var.db_names
    public_ips  = var.db_public_ips
    private_ips = var.db_private_ips
    region      = var.region

    aws_bot_access_key = var.aws_bot_access_key
    aws_bot_secret_key = var.aws_bot_secret_key

    docker_engine_install_url = var.docker_engine_install_url
    consul_version        = var.consul_version

    consul_lan_leader_ip = local.consul_lan_leader_ip
    consul_adv_addresses = local.consul_db_adv_addresses

    role = "db"
}

module "db_hostname" {
    source = "./modules/hostname"

    server_name_prefix = var.server_name_prefix
    region = var.region

    hostname = var.root_domain_name
    names = var.db_names
    servers = var.db_servers
    public_ips = var.db_public_ips
    alt_hostname = var.root_domain_name
}

module "db_cron" {
    source = "./modules/cron"

    role = "db"
    aws_bucket_region = var.aws_bucket_region
    aws_bucket_name = var.aws_bucket_name
    servers = var.db_servers
    public_ips = var.db_public_ips

    templates = {
        redisdb = "redisdb.tmpl"
        mongodb = "mongodb.tmpl"
        pgdb = "pgdb.tmpl"
    }
    destinations = {
        redisdb = "/root/code/cron/redisdb.cron"
        mongodb = "/root/code/cron/mongodb.cron"
        pgdb = "/root/code/cron/pgdb.cron"
    }
    remote_exec = [
        "cd /root/code/cron",
        "cat redisdb.cron mongodb.cron pgdb.cron > /root/code/cron/db.cron",
        "crontab /root/code/cron/db.cron",
        "crontab -l"
    ]

    # DB specific
    num_dbs = length(var.dbs_to_import)
    redis_dbs = length(local.redis_dbs) > 0 ? local.redis_dbs : []
    mongo_dbs = length(local.mongo_dbs) > 0 ? local.mongo_dbs : []
    pg_dbs = length(local.pg_dbs) > 0 ? local.pg_dbs : []
    pg_fn = length(local.pg_fn) > 0 ? local.pg_fn["pg"] : "" # TODO: hack
    prev_module_output = module.db_provisioners.output
}

module "db_provision_files" {
    source = "./modules/provision"

    role = "db"
    servers = var.db_servers
    public_ips = var.db_public_ips

    private_ips = var.db_private_ips
    import_dbs = var.import_dbs
    db_backups_enabled = var.db_backups_enabled

    known_hosts = var.known_hosts
    active_env_provider = var.active_env_provider
    root_domain_name = var.root_domain_name
    deploy_key_location = var.deploy_key_location
    pg_read_only_pw = var.pg_read_only_pw
    prev_module_output = module.db_cron.output
}

resource "null_resource" "install_dbs" {
    count      = var.db_servers > 0 ? var.db_servers : 0
    depends_on = [
        module.db_provisioners,
        module.db_hostname,
        module.db_cron,
        module.db_provision_files,
    ]

    provisioner "remote-exec" {
        # TODO: Setup to bind to private net/vpc instead of relying soley on the security group/firewall for all dbs
        inline = [
            "chmod +x /root/code/scripts/install_redis.sh",
            "chmod +x /root/code/scripts/install_mongo.sh",
            "chmod +x /root/code/scripts/install_pg.sh",
            (length(local.redis_dbs) > 0
                ? "bash /root/code/scripts/install_redis.sh -v 5.0.9;"
                : "echo 0;"),
            (length(local.mongo_dbs) > 0
                ? "bash /root/code/scripts/install_mongo.sh -v 4.2.7 -i ${element(var.active_env_provider == "aws" ? var.db_private_ips : var.db_public_ips, count.index)};"
                : "echo 0;"),
            (length(local.pg_dbs) > 0
                ? "bash /root/code/scripts/install_pg.sh -v 9.5;"
                : "echo 0;"),
            "exit 0;"
        ]
    }
    connection {
        host = element(var.db_public_ips, count.index)
        type = "ssh"
    }
}

resource "null_resource" "import_dbs" {
    count = var.import_dbs && var.db_servers > 0 ? length(var.dbs_to_import) : 0
    depends_on = [
        module.db_provisioners,
        module.db_hostname,
        module.db_cron,
        module.db_provision_files,
        null_resource.install_dbs
    ]

    provisioner "file" {
        content = <<-EOF
            IMPORT=${var.dbs_to_import[count.index]["import"]};
            DB_TYPE=${var.dbs_to_import[count.index]["type"]};
            AWS_BUCKET_NAME=${var.dbs_to_import[count.index]["aws_bucket"]};
            AWS_BUCKET_REGION=${var.dbs_to_import[count.index]["aws_region"]};
            DB_NAME=${var.dbs_to_import[count.index]["dbname"]};
            HOST=${element(var.active_env_provider == "aws" ? var.db_private_ips : var.db_public_ips, count.index)}

            if [ "$IMPORT" = "true" ] && [ "$DB_TYPE" = "mongo" ]; then
                bash /root/code/scripts/import_mongo_db.sh -r $AWS_BUCKET_REGION -b $AWS_BUCKET_NAME -d $DB_NAME -h $HOST;
                cp /etc/consul.d/templates/mongo.json /etc/consul.d/conf.d/mongo.json
            fi

            if [ "$IMPORT" = "true" ] && [ "$DB_TYPE" = "pg" ]; then
                bash /root/code/scripts/import_pg_db.sh -r $AWS_BUCKET_REGION -b $AWS_BUCKET_NAME -d $DB_NAME;
                cp /etc/consul.d/templates/pg.json /etc/consul.d/conf.d/pg.json
            fi

            if [ "$IMPORT" = "true" ] && [ "$DB_TYPE" = "redis" ]; then
                bash /root/code/scripts/import_redis_db.sh -r $AWS_BUCKET_REGION -b $AWS_BUCKET_NAME -d $DB_NAME;
                cp /etc/consul.d/templates/redis.json /etc/consul.d/conf.d/redis.json
            fi
        EOF
        destination = "/tmp/import_dbs-${count.index}.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/import_dbs-${count.index}.sh",
            "/tmp/import_dbs-${count.index}.sh"
        ]
    }

    connection {
        # TODO: Determine how to handle multiple db servers
        host = element(var.db_public_ips, 0)
        type = "ssh"
    }
}


resource "null_resource" "db_ready" {
    count = var.db_servers
    depends_on = [
        module.db_provisioners,
        module.db_hostname,
        module.db_cron,
        module.db_provision_files,
        null_resource.install_dbs,
        null_resource.import_dbs,
    ]

    provisioner "remote-exec" {
        inline = [
            "consul reload",
            "consul kv put init/db_bootstrapped true;"
        ]
    }

    connection {
        host = element(var.db_public_ips, count.index)
        type = "ssh"
    }
}
