output "instance" {
    value = {
        (digitalocean_droplet.main.name) = "ssh root@${digitalocean_droplet.main.ipv4_address}"
    }
}

output "ansible_host" {
    value = {
        name = digitalocean_droplet.main.name
        roles = var.servers.roles
        ip = digitalocean_droplet.main.ipv4_address
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
