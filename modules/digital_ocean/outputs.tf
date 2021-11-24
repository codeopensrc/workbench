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

output "ansible_hosts" {
    value = local.sorted_hosts
}
