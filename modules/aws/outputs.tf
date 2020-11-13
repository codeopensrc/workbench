
output "instances" {
    value = {
        for SERVER in aws_instance.main[*]:
        (SERVER.tags.Name) => "ssh root@${SERVER.public_ip}"
    }
}

output "admin_private_ip_addresses" {
    value = [
        for SERVER in aws_instance.main[*]:
        SERVER.private_ip
        if length(regexall("admin", SERVER.tags.Roles)) > 0
    ]
}
output "admin_public_ip_addresses" {
    value = [
        for SERVER in aws_instance.main[*]:
        SERVER.public_ip
        if length(regexall("admin", SERVER.tags.Roles)) > 0
    ]
}
output "admin_names" {
    value = [
        for SERVER in aws_instance.main[*]:
        SERVER.tags.Name
        if length(regexall("admin", SERVER.tags.Roles)) > 0
    ]
}



output "lead_private_ip_addresses" {
    value = [
        for SERVER in aws_instance.main[*]:
        SERVER.private_ip
        if length(regexall("lead", SERVER.tags.Roles)) > 0
    ]
}
output "lead_public_ip_addresses" {
    value = [
        for SERVER in aws_instance.main[*]:
        SERVER.public_ip
        if length(regexall("lead", SERVER.tags.Roles)) > 0
    ]
}
output "lead_names" {
    value = [
        for SERVER in aws_instance.main[*]:
        SERVER.tags.Name
        if length(regexall("lead", SERVER.tags.Roles)) > 0
    ]
}



output "db_private_ip_addresses" {
    value = [
        for SERVER in aws_instance.main[*]:
        SERVER.private_ip
        if length(regexall("db", SERVER.tags.Roles)) > 0
    ]
}
output "db_public_ip_addresses" {
    value = [
        for SERVER in aws_instance.main[*]:
        SERVER.public_ip
        if length(regexall("db", SERVER.tags.Roles)) > 0
    ]
}
output "db_names" {
    value = [
        for SERVER in aws_instance.main[*]:
        SERVER.tags.Name
        if length(regexall("db", SERVER.tags.Roles)) > 0
    ]
}
output "db_ids" {
    value = [
        for SERVER in aws_instance.main[*]:
        SERVER.id
        if length(regexall("db", SERVER.tags.Roles)) > 0
    ]
}
