output "admin_private_ip_addresses" { value = aws_instance.admin[*].private_ip }
output "admin_public_ip_addresses" { value = aws_instance.admin[*].public_ip }
output "admin_names" { value = aws_instance.admin[*].tags.Name }

output "lead_private_ip_addresses" { value = aws_instance.lead[*].private_ip }
output "lead_public_ip_addresses" { value = aws_instance.lead[*].public_ip }
output "lead_names" { value = aws_instance.lead[*].tags.Name }

output "build_private_ip_addresses" { value = aws_instance.build[*].private_ip }
output "build_public_ip_addresses" { value = aws_instance.build[*].public_ip }
output "build_names" { value = aws_instance.build[*].tags.Name }

output "db_private_ip_addresses" { value = aws_instance.db[*].private_ip }
output "db_public_ip_addresses" { value = aws_instance.db[*].public_ip }
output "db_names" { value = aws_instance.db[*].tags.Name }
output "db_ids" { value = aws_instance.db[*].id }

output "dev_private_ip_addresses" { value = aws_instance.dev[*].private_ip }
output "dev_public_ip_addresses" { value = aws_instance.dev[*].public_ip }
output "dev_names" { value = aws_instance.dev[*].tags.Name }

output "mongo_private_ip_addresses" { value = aws_instance.mongo[*].private_ip }
output "mongo_public_ip_addresses" { value = aws_instance.mongo[*].public_ip }
output "mongo_names" { value = aws_instance.mongo[*].tags.Name }
output "mongo_ids" { value = aws_instance.mongo[*].id }

output "pg_private_ip_addresses" { value = aws_instance.pg[*].private_ip }
output "pg_public_ip_addresses" { value = aws_instance.pg[*].public_ip }
output "pg_names" { value = aws_instance.pg[*].tags.Name }
output "pg_ids" { value = aws_instance.pg[*].id }

output "redis_private_ip_addresses" { value = aws_instance.redis[*].private_ip }
output "redis_public_ip_addresses" { value = aws_instance.redis[*].public_ip }
output "redis_names" { value = aws_instance.redis[*].tags.Name }
output "redis_ids" { value = aws_instance.redis[*].id }

output "web_private_ip_addresses" { value = aws_instance.web[*].private_ip }
output "web_public_ip_addresses" { value = aws_instance.web[*].public_ip }
output "web_names" { value = aws_instance.web[*].tags.Name }
