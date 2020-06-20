# module "provisioners" {
#     source      = "../../provisioners"
#     servers     = var.admin_servers
#     names       = var.admin_names
#     public_ips  = var.admin_public_ips
#     private_ips = var.admin_private_ips
#     region      = var.region
#
#     aws_bot_access_key = var.aws_bot_access_key
#     aws_bot_secret_key = var.aws_bot_secret_key
#
#     known_hosts = var.known_hosts
#     deploy_key_location = var.deploy_key_location
#     root_domain_name = var.root_domain_name
#
#     docker_compose_version = var.docker_compose_version
#     docker_engine_install_url  = var.docker_engine_install_url
#     consul_version         = var.consul_version
#
#     # TODO: This might cause a problem when launching the 2nd admin server when swapping
#     consul_lan_leader_ip = local.consul_lan_leader_ip
#     consul_adv_addresses = local.consul_admin_adv_addresses
#
#     role = "admin"
# }
#
# module "change_hostname" {
#     source = "./modules/change_hostname.tf"
#
#     hostname = var.gitlab_server_url
#     server_name_prefix = var.server_name_prefix
#     region = var.region
#     names = var.admin_names
#     public_ips = var.admin_public_ips
#     alt_hostname = "chef"
# }
#
#
# resource "null_resource" "cron_admin" {
#     count      = var.admin_servers > 0 ? var.admin_servers : 0
#     depends_on = [module.admin_provisioners]
#
#     provisioner "remote-exec" {
#         inline = [ "mkdir -p /root/code/cron" ]
#     }
#     provisioner "file" {
#         content = fileexists("${path.module}/template_files/cron/admin.tmpl") ? templatefile("${path.module}/template_files/cron/admin.tmpl", {
#             gitlab_backups_enabled = var.gitlab_backups_enabled
#             aws_bucket_region = var.aws_bucket_region
#             aws_bucket_name = var.aws_bucket_name
#         }) : ""
#         destination = "/root/code/cron/admin.cron"
#     }
#     provisioner "remote-exec" {
#         inline = [ "crontab /root/code/cron/admin.cron", "crontab -l" ]
#     }
#     connection {
#         host = element(var.admin_public_ips, count.index)
#         type = "ssh"
#     }
# }
