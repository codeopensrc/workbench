output "instances" {
    value = {
        for h in digitalocean_droplet.main:
        (h.name) => "ssh root@${h.ipv4_address}"
    }
}

output "ansible_hosts" {
    value = local.sorted_hosts
}
