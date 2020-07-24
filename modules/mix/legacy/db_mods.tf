### NOTE: The goal is to turn these into "roles" that can all be applied to the
###   same server and also multiple servers to scale
###  IE, In one env, it has 1 server that does all: leader, admin, and db
###  Another can have 1 server as admin and leader with seperate db server
###  Another can have 1 server with all roles and scale out aditional servers as leader servers
###  Simplicity/Flexibility/Adaptability

# Figure out way to only run
# db_provisioners
# db_hostname
# db_cron
# db_provision_files
# when not admin ip

# module "db_provisioners" {
#     source      = "./modules/misc"
#     servers     = var.db_servers
#     names       = var.db_names
#     public_ips  = var.db_public_ips
#     private_ips = var.db_private_ips
#     region      = var.region
#
#     aws_bot_access_key = var.aws_bot_access_key
#     aws_bot_secret_key = var.aws_bot_secret_key
#
#     docker_engine_install_url = var.docker_engine_install_url
#     consul_version        = var.consul_version
#
#     consul_lan_leader_ip = local.consul_lan_leader_ip
#     consul_adv_addresses = local.consul_db_adv_addresses
#
#     # role = "db"
#     roles = ["db"]
# }
#
# module "db_hostname" {
#     source = "./modules/hostname"
#
#     server_name_prefix = var.server_name_prefix
#     region = var.region
#
#     hostname = var.root_domain_name
#     names = var.db_names
#     servers = var.db_servers
#     public_ips = var.db_public_ips
#     private_ips = var.db_private_ips
#     root_domain_name = var.root_domain_name
#     prev_module_output = module.db_provisioners.output
# }
#
# module "db_cron" {
#     source = "./modules/cron"
#
#     # role = "db"
#     roles = ["db"]
#     aws_bucket_region = var.aws_bucket_region
#     aws_bucket_name = var.aws_bucket_name
#     servers = var.db_servers
#     public_ips = var.db_public_ips
#
#     templates = {
#         redisdb = "redisdb.tmpl"
#         mongodb = "mongodb.tmpl"
#         pgdb = "pgdb.tmpl"
#     }
#     destinations = {
#         redisdb = "/root/code/cron/redisdb.cron"
#         mongodb = "/root/code/cron/mongodb.cron"
#         pgdb = "/root/code/cron/pgdb.cron"
#     }
#     remote_exec = [
#         "cd /root/code/cron",
#         "cat redisdb.cron mongodb.cron pgdb.cron > /root/code/cron/db.cron",
#         "crontab /root/code/cron/db.cron",
#         "crontab -l"
#     ]
#
#     # DB specific
#     num_dbs = length(var.dbs_to_import)
#     db_backups_enabled = var.db_backups_enabled
#     redis_dbs = length(local.redis_dbs) > 0 ? local.redis_dbs : []
#     mongo_dbs = length(local.mongo_dbs) > 0 ? local.mongo_dbs : []
#     pg_dbs = length(local.pg_dbs) > 0 ? local.pg_dbs : []
#     pg_fn = length(local.pg_fn) > 0 ? local.pg_fn["pg"] : "" # TODO: hack
#     prev_module_output = module.db_provisioners.output
# }
#
# module "db_provision_files" {
#     source = "./modules/provision"
#
#     servers = var.db_servers
#     public_ips = var.db_public_ips
#     private_ips = var.db_private_ips
#
#     known_hosts = var.known_hosts
#     active_env_provider = var.active_env_provider
#     root_domain_name = var.root_domain_name
#     deploy_key_location = var.deploy_key_location
#     pg_read_only_pw = var.pg_read_only_pw
#     prev_module_output = module.db_cron.output
# }
