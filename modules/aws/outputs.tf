
output "instances" {
    value = zipmap(
        flatten([
            for SERVER in local.all_server_instances[*]:
            keys(SERVER)
        ]),
        flatten([
            for SERVER in local.all_server_instances[*]:
            values(SERVER)
        ])
    )
}

### This output depends on the full module
output "ansible_hosts" {
    value = local.sorted_hosts
}

### These outputs only depend on the data resource
### They will output BEFORE any destroys on an instance/resource -- Important
output "admin_private_ip_addresses" {
    value = local.admin_private_ips
}
output "admin_public_ip_addresses" {
    value = local.admin_public_ips 
}
output "admin_names" {
    value = local.admin_names
}

output "lead_private_ip_addresses" {
    value = local.lead_private_ips
}
output "lead_public_ip_addresses" {
    value = local.lead_public_ips
}
output "lead_names" {
    value = local.lead_names
}

output "db_private_ip_addresses" {
    value = local.db_private_ips
}
output "db_public_ip_addresses" {
    value = local.db_public_ips
}
output "db_names" {
    value = local.db_names
}

output "build_private_ip_addresses" {
    value = local.build_private_ips
}
output "build_public_ip_addresses" {
    value = local.build_public_ips
}
output "build_names" {
    value = local.build_names
}
