output "instances" {
    value = {
        for k, h in azurerm_linux_virtual_machine.main:
        (h.name) => "${k} - ssh root@${h.public_ip_address}"
    }
}

output "ansible_hosts" {
    value = local.sorted_hosts
}
