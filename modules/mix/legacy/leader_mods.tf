### NOTE: The goal is to turn these into "roles" that can all be applied to the
###   same server and also multiple servers to scale
###  IE, In one env, it has 1 server that does all: leader, admin, and db
###  Another can have 1 server as admin and leader with seperate db server
###  Another can have 1 server with all roles and scale out aditional servers as leader servers
###  Simplicity/Flexibility/Adaptability
# module "leader_provisioners" {
#     source      = "./modules/misc"
#     servers     = var.leader_servers
#     names       = var.lead_names
#     public_ips  = var.lead_public_ips
#     private_ips = var.lead_private_ips
#     region      = var.region
#
#     aws_bot_access_key = var.aws_bot_access_key
#     aws_bot_secret_key = var.aws_bot_secret_key
#
#     docker_engine_install_url  = var.docker_engine_install_url
#     consul_version         = var.consul_version
#
#     join_machine_id = var.join_machine_id
#
#     # consul_wan_leader_ip = var.aws_leaderIP
#     consul_wan_leader_ip = var.external_leaderIP
#
#     consul_lan_leader_ip = local.consul_lan_leader_ip
#     consul_adv_addresses = local.consul_lead_adv_addresses
#
#     datacenter_has_admin = length(var.admin_public_ips) > 0
#
#     # role = "manager"
#     roles = ["lead"]
# }

# module "leader_hostname" {
#     source = "./modules/hostname"
#
#     server_name_prefix = var.server_name_prefix
#     region = var.region
#
#     hostname = var.root_domain_name
#     names = var.lead_names
#     servers = var.leader_servers
#     public_ips = var.lead_public_ips
#     private_ips = var.lead_private_ips
#     root_domain_name = var.root_domain_name
#     prev_module_output = module.leader_provisioners.output
# }

# module "leader_cron" {
#     source = "./modules/cron"
#
#     # role = "lead"
#     roles = ["lead"]
#     aws_bucket_region = var.aws_bucket_region
#     aws_bucket_name = var.aws_bucket_name
#     servers = var.leader_servers
#     public_ips = var.lead_public_ips
#
#     templates = {
#         leader = "leader.tmpl"
#     }
#     destinations = {
#         leader = "/root/code/cron/leader.cron"
#     }
#     remote_exec = ["crontab /root/code/cron/leader.cron", "crontab -l"]
#
#     # Leader specific
#     run_service = var.run_service_enabled
#     send_logs = var.send_logs_enabled
#     send_jsons = var.send_jsons_enabled
#
#     # Temp Leader specific
#     docker_service_name = local.docker_service_name
#     consul_service_name = local.consul_service_name
#     folder_location = local.folder_location
#     logs_prefix = local.logs_prefix
#     email_image = local.email_image
#     service_repo_name = local.service_repo_name
#     prev_module_output = module.leader_provisioners.output
# }

# module "leader_provision_files" {
#     source = "./modules/provision"
#
#     servers = var.leader_servers
#     public_ips = var.lead_public_ips
#     private_ips = var.lead_private_ips
#
#     known_hosts = var.known_hosts
#     deploy_key_location = var.deploy_key_location
#     root_domain_name = var.root_domain_name
#     prev_module_output = module.leader_cron.output
# }
