output "instances" {
    value = {
        for k, h in aws_instance.main:
        (h.tags.Name) => "${k} - ssh root@${h.public_ip}"
    }
}
output "ansible_hosts" {
    value = local.sorted_hosts
}
