output "admin_private_ip_addresses" { value = digitalocean_droplet.admin[*].ipv4_address }
output "admin_public_ip_addresses" { value = digitalocean_droplet.admin[*].ipv4_address }
output "admin_names" { value = digitalocean_droplet.admin[*].name }

output "lead_private_ip_addresses" { value = digitalocean_droplet.lead[*].ipv4_address }
output "lead_public_ip_addresses" { value = digitalocean_droplet.lead[*].ipv4_address }
output "lead_names" { value = digitalocean_droplet.lead[*].name }

output "build_private_ip_addresses" { value = digitalocean_droplet.build[*].ipv4_address }
output "build_public_ip_addresses" { value = digitalocean_droplet.build[*].ipv4_address }
output "build_names" { value = digitalocean_droplet.build[*].name }

output "db_private_ip_addresses" { value = digitalocean_droplet.db[*].ipv4_address }
output "db_public_ip_addresses" { value = digitalocean_droplet.db[*].ipv4_address }
output "db_names" { value = digitalocean_droplet.db[*].name }
output "db_ids" { value = digitalocean_droplet.db[*].id }

output "dev_private_ip_addresses" { value = digitalocean_droplet.dev[*].ipv4_address }
output "dev_public_ip_addresses" { value = digitalocean_droplet.dev[*].ipv4_address }
output "dev_names" { value = digitalocean_droplet.dev[*].name }

output "mongo_private_ip_addresses" { value = digitalocean_droplet.mongo[*].ipv4_address }
output "mongo_public_ip_addresses" { value = digitalocean_droplet.mongo[*].ipv4_address }
output "mongo_names" { value = digitalocean_droplet.mongo[*].name }
output "mongo_ids" { value = digitalocean_droplet.mongo[*].id }

output "pg_private_ip_addresses" { value = digitalocean_droplet.pg[*].ipv4_address }
output "pg_public_ip_addresses" { value = digitalocean_droplet.pg[*].ipv4_address }
output "pg_names" { value = digitalocean_droplet.pg[*].name }
output "pg_ids" { value = digitalocean_droplet.pg[*].id }

output "redis_private_ip_addresses" { value = digitalocean_droplet.redis[*].ipv4_address }
output "redis_public_ip_addresses" { value = digitalocean_droplet.redis[*].ipv4_address }
output "redis_names" { value = digitalocean_droplet.redis[*].name }
output "redis_ids" { value = digitalocean_droplet.redis[*].id }

output "web_private_ip_addresses" { value = digitalocean_droplet.web[*].ipv4_address }
output "web_public_ip_addresses" { value = digitalocean_droplet.web[*].ipv4_address }
output "web_names" { value = digitalocean_droplet.web[*].name }
