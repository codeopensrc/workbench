output "instances" {
    value = {
        for h in aws_instance.main:
        (h.tags.Name) => "ssh root@${h.public_ip}"
    }
}
output "ansible_hosts" {
    value = local.sorted_hosts
}
