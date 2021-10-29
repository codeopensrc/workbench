output "instance" {
    value = {
        (aws_instance.main.tags.Name) = "ssh root@${aws_instance.main.public_ip}"
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
