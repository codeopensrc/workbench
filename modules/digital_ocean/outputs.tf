
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
    value = local.all_lead_private_ips
}
output "lead_public_ip_addresses" {
    value = local.all_lead_public_ips
}
output "lead_names" {
    value = local.all_lead_names
}

output "db_private_ip_addresses" {
    value = local.all_db_private_ips
}
output "db_public_ip_addresses" {
    value = local.all_db_public_ips
}
output "db_names" {
    value = local.all_db_names
}

output "db_ids" {
    value = local.all_db_server_ids
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
