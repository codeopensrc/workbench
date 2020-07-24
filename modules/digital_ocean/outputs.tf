output "admin_private_ip_addresses" { value = digitalocean_droplet.admin[*].ipv4_address }
output "admin_public_ip_addresses" { value = digitalocean_droplet.admin[*].ipv4_address }
output "admin_names" { value = digitalocean_droplet.admin[*].name }

output "lead_private_ip_addresses" { value = digitalocean_droplet.lead[*].ipv4_address }
output "lead_public_ip_addresses" { value = digitalocean_droplet.lead[*].ipv4_address }
output "lead_names" { value = digitalocean_droplet.lead[*].name }

output "db_private_ip_addresses" { value = digitalocean_droplet.db[*].ipv4_address }
output "db_public_ip_addresses" { value = digitalocean_droplet.db[*].ipv4_address }
output "db_names" { value = digitalocean_droplet.db[*].name }
output "db_ids" { value = digitalocean_droplet.db[*].id }
