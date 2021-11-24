output "instance" {
    value = {
        (digitalocean_droplet.main.name) = "ssh root@${digitalocean_droplet.main.ipv4_address}"
    }
}
locals {
    ##TODO: Dynamic or list all sizes
    size_priority = {
        "s-1vcpu-1gb" = "1",
        "s-1vcpu-2gb" = "2",
        "s-2vcpu-2gb" = "3",
        "s-2vcpu-4gb" = "4",
        "s-4vcpu-8gb" = "5",
    }
}
resource "time_static" "creation_time" {}

output "ansible_host" {
    value = {
        machine_id = digitalocean_droplet.main.id
        name = digitalocean_droplet.main.name
        roles = var.servers.roles
        ip = digitalocean_droplet.main.ipv4_address
        private_ip = digitalocean_droplet.main.ipv4_address_private
        creation_time = time_static.creation_time.id
        size_priority = local.size_priority[var.servers.size["digital_ocean"]]
    }
}

output "private_ip" {
    value = digitalocean_droplet.main.ipv4_address_private
}
output "public_ip" {
    value = digitalocean_droplet.main.ipv4_address
}
output "name" {
    value = digitalocean_droplet.main.name
}
output "id" {
    value = digitalocean_droplet.main.id
}
output "tags" {
    value = digitalocean_droplet.main.tags
}
