
output "instances" {
    value = {
        for SERVER in digitalocean_droplet.main[*]:
        (SERVER.name) => "ssh root@${SERVER.ipv4_address}"
        if length(join(",", SERVER.tags)) > 0
    }
}

output "admin_private_ip_addresses" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.ipv4_address_private
        if length(regexall("admin", join(",", SERVER.tags))) > 0
    ]
}
output "admin_public_ip_addresses" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.ipv4_address
        if length(regexall("admin", join(",", SERVER.tags))) > 0
    ]
}
output "admin_names" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.name
        if length(regexall("admin", join(",", SERVER.tags))) > 0
    ]
}



output "lead_private_ip_addresses" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.ipv4_address_private
        if length(regexall("lead", join(",", SERVER.tags))) > 0
    ]
}
output "lead_public_ip_addresses" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.ipv4_address
        if length(regexall("lead", join(",", SERVER.tags))) > 0
    ]
}
output "lead_names" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.name
        if length(regexall("lead", join(",", SERVER.tags))) > 0
    ]
}



output "db_private_ip_addresses" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.ipv4_address_private
        if length(regexall("db", join(",", SERVER.tags))) > 0
    ]
}
output "db_public_ip_addresses" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.ipv4_address
        if length(regexall("db", join(",", SERVER.tags))) > 0
    ]
}
output "db_names" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.name
        if length(regexall("db", join(",", SERVER.tags))) > 0
    ]
}


output "db_ids" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.id
        if length(regexall("db", join(",", SERVER.tags))) > 0
    ]
}



output "build_private_ip_addresses" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.ipv4_address_private
        if length(regexall("build", join(",", SERVER.tags))) > 0
    ]
}
output "build_public_ip_addresses" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.ipv4_address
        if length(regexall("build", join(",", SERVER.tags))) > 0
    ]
}
output "build_names" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.name
        if length(regexall("build", join(",", SERVER.tags))) > 0
    ]
}
