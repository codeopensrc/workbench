output "instance" {
    value = {
        (aws_instance.main.tags.Name) = "ssh root@${aws_instance.main.public_ip}"
    }
}
locals {
    ##TODO: Dynamic or list all sizes
    size_priority = {
        "t3a.micro" = "1",
        "t3a.small" = "2",
        "t3a.medium" = "3",
        "t3a.large" = "4",
    }
}
resource "time_static" "creation_time" {}

output "ansible_host" {
    value = {
        name = aws_instance.main.tags.Name
        roles = var.servers.roles
        ip = aws_instance.main.public_ip
        private_ip = aws_instance.main.private_ip
        creation_time = time_static.creation_time.id
        size_priority = local.size_priority[var.servers.size["aws"]]
    }
}

output "private_ip" {
    value = aws_instance.main.private_ip
}
output "public_ip" {
    value = aws_instance.main.public_ip
}
output "name" {
    value = aws_instance.main.tags.Name
}
output "id" {
    value = aws_instance.main.id
}
output "tags" {
    value = aws_instance.main.tags
}
