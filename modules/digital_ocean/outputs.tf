output "instances" {
    value = {
        for k, h in digitalocean_droplet.main:
        (h.name) => "${k} - ssh root@${h.ipv4_address}"
    }
}

output "ansible_hosts" {
    value = local.sorted_hosts
}
