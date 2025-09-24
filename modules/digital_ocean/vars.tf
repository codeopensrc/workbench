### See envs/env/main.tf locals.config
variable "config" {}
variable "helm_experiments" { ephemeral = true }
variable "stun_protos" { default = ["tcp", "udp"] }

## dns
locals {
    cname_additional_aliases = flatten([
        for domainname, domain in var.config.additional_domains : [
            for subdomainname, redirect in domain: {
                domainname = domainname
                subdomainname = subdomainname
            }
            if subdomainname != "@"
        ]
    ])
    cname_misc_aliases = flatten(var.config.misc_cnames)
}

## kubernetes
locals {
    lb_http_nodeport = var.config.kubernetes_nginx_nodeports.http ## Must be valid kubernetes nodeport: 30000-32767
    lb_https_nodeport = var.config.kubernetes_nginx_nodeports.https ## Must be valid kubernetes nodeport: 30000-32767
    lb_starting_udp_nodeport = 31100
    lb_starting_tcp_nodeport = 31200
    lb_udp_nodeports = {
        for ind, port in keys(lookup(var.config.kubernetes_nginx_nodeports, "udp", {})):
        "${port}" => sum([local.lb_starting_udp_nodeport, ind])
    }
    lb_tcp_nodeports = {
        for ind, port in keys(lookup(var.config.kubernetes_nginx_nodeports, "tcp", {})):
        "${port}" => sum([local.lb_starting_tcp_nodeport, ind])
    }
}



## TODO: The logic in this grouping was impressive and keeping it around for reference
## sorted machines by creation time then size
locals {
    #all_ansible_hosts = tolist([
    #    for CFG in local.cfg_servers: {
    #        key = CFG.key
    #        machine_id = digitalocean_droplet.main[CFG.key].id
    #        name = digitalocean_droplet.main[CFG.key].name
    #        roles = CFG.roles
    #        role = CFG.role
    #        ip = digitalocean_droplet.main[CFG.key].ipv4_address
    #        private_ip = digitalocean_droplet.main[CFG.key].ipv4_address_private
    #        creation_time = time_static.creation_time[CFG.key].id
    #        size_priority = CFG.size_priority
    #    }
    #])

    ### Creates { role1=[{host}...], role2=[{host}...] }
    #role_grouped_hosts = {
    #    for ind, host in local.all_ansible_hosts: (host.role) => host...
    #}
    ### Creates { role1={timestamp=[{host}...], timestamp2=[{host}...]}, role2={timestamp=[{host}...]} }
    #time_grouped_hosts = {
    #    for role, hosts in local.role_grouped_hosts:
    #    (role) => { for host in hosts: (host.creation_time) => host... }
    #}
    ### Creates { role1={timestamp={size=[{host}...], size2=[{host}...]}, timestamp2={size=[{host}...]}}, role2={timestamp={size=[{host}...]}} }
    #size_grouped_hosts = {
    #    for role, times in local.time_grouped_hosts:
    #    (role) => { for time, hosts in times:
    #        (time) => { for host in hosts: (host.size_priority) => host... }
    #    }
    #}
    ### Creates { role1=[all_distinct_creation_times...], role2=[all_distinct_creation_times...] }
    #sorted_times = {
    #    for role, hosts in local.role_grouped_hosts:
    #    (role) => sort(distinct([ for host in hosts: host.creation_time ]))
    #}
    ### Creates { role1=[all_distinct_sizes...], role2=[all_distinct_sizes...] }
    #sorted_sizes = {
    #    for role, hosts in local.role_grouped_hosts:
    #    (role) => reverse(sort(distinct([ for host in hosts: host.size_priority ])))
    #}

    ### Groups hosts back into {role1=[{host}...], role2=[{host}...]}
    ### Hosts grouped by role are sorted by creation_time first -> size
    ### Intent is to have DNS point to the oldest/largest server
    #sorted_hosts = {
    #    for role, times in local.sorted_times: (role) => flatten([
    #        for time in times: [
    #            for size in local.sorted_sizes[role]:
    #            local.size_grouped_hosts[role][time][size]
    #            if lookup(local.size_grouped_hosts[role][time], size, "") != ""
    #        ]
    #    ])
    #}
}
