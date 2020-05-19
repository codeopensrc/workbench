# output "admin_ip" {
#     value = element(concat(var.admin_public_ips, [""]), 0)
# }
# output "admin_name" {
#     value = element(concat(var.admin_names, [""]), 0)
# }
# output "chef_id" {
#     value = element(concat(null_resource.upload_chef_cookbooks.*.id, [""]), 0)
# }
