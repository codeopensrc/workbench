
output "instances" {
    value = {
        for SERVER in digitalocean_droplet.main[*]:
        (SERVER.name) => "ssh root@${SERVER.ipv4_address}"
    }
}
output "ipv4_addresses_private" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.ipv4_address_private
    ]
}
output "ipv4_addresses" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.ipv4_address
    ]
}
output "names" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.name
    ]
}
output "ids" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.id
    ]
}
output "tags" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.tags
    ]
}



## If admin also has the lead role
## Not ideal, but itll get the job done allowing db + lead + admin till refactor
## See ../vars.tf locals how we might fix
output "ipv4_addresses_extra_lead" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.ipv4_address
        if contains(SERVER.tags, "lead")
    ]
}
output "ipv4_addresses_private_extra_lead" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.ipv4_address_private
        if contains(SERVER.tags, "lead")
    ]
}
output "names_extra_lead" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.name
        if contains(SERVER.tags, "lead")
    ]
}
output "ids_extra_lead" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.id
        if contains(SERVER.tags, "lead")
    ]
}


## If admin also has the db role
## Not ideal, but itll get the job done allowing db + lead + admin till refactor
## See ../vars.tf locals how we might fix
output "ipv4_addresses_extra_db" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.ipv4_address
        if contains(SERVER.tags, "db")
    ]
}
output "ipv4_addresses_private_extra_db" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.ipv4_address_private
        if contains(SERVER.tags, "db")
    ]
}
output "names_extra_db" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.name
        if contains(SERVER.tags, "db")
    ]
}
output "ids_extra_db" {
    value = [
        for SERVER in digitalocean_droplet.main[*]:
        SERVER.id
        if contains(SERVER.tags, "db")
    ]
}

