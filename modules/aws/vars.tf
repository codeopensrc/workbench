### See envs/env/main.tf locals.config
variable "config" {}

variable "stun_protos" { default = ["tcp", "udp"] }

## input/config
locals {
    ##TODO: Dynamic or list all sizes
    ### Some sizes for reference
    #t3a.large  = 2vcpu 8gbMem
    #t3a.medium = 2vcpu 4gbMem
    #t3a.small  = 2vcpu 2gbMem
    #t3a.micro  = 2vcpu 1gbMem 
    #t3a.nano   = 2vcpu .5gbMem 
    size_priority = {
        "t3a.micro" = "1",
        "t3a.small" = "2",
        "t3a.medium" = "3",
        "t3a.large" = "4",
    }
    cfg_servers = flatten([
        for ind, SERVER in var.config.servers: [
            for num in range(0, SERVER.count): {
                key = "${SERVER.fleet}-n${num}"
                server = SERVER
                role = SERVER.roles[0]
                roles = SERVER.roles
                size_priority = local.size_priority[SERVER.size["aws"]]
                image_alias = local.image_alias[SERVER.roles[0]]
            }
        ]
    ])
}

## sorted machines by creation time then size
locals {
    has_admin = contains(flatten(local.cfg_servers[*].roles), "admin")

    all_ansible_hosts = tolist([
        for CFG in local.cfg_servers: {
            key = CFG.key
            machine_id = aws_instance.main[CFG.key].id
            name = aws_instance.main[CFG.key].tags.Name
            roles = CFG.roles
            role = CFG.role
            ip = aws_instance.main[CFG.key].public_ip
            private_ip = aws_instance.main[CFG.key].private_ip
            creation_time = time_static.creation_time[CFG.key].id
            size_priority = CFG.size_priority
        }
    ])

    ## Creates { role1=[{host}...], role2=[{host}...] }
    role_grouped_hosts = {
        for ind, host in local.all_ansible_hosts: (host.role) => host...
    }
    ## Creates { role1={timestamp=[{host}...], timestamp2=[{host}...]}, role2={timestamp=[{host}...]} }
    time_grouped_hosts = {
        for role, hosts in local.role_grouped_hosts:
        (role) => { for host in hosts: (host.creation_time) => host... }
    }
    ## Creates { role1={timestamp={size=[{host}...], size2=[{host}...]}, timestamp2={size=[{host}...]}}, role2={timestamp={size=[{host}...]}} }
    size_grouped_hosts = {
        for role, times in local.time_grouped_hosts:
        (role) => { for time, hosts in times:
            (time) => { for host in hosts: (host.size_priority) => host... }
        }
    }
    ## Creates { role1=[all_distinct_creation_times...], role2=[all_distinct_creation_times...] }
    sorted_times = {
        for role, hosts in local.role_grouped_hosts:
        (role) => sort(distinct([ for host in hosts: host.creation_time ]))
    }
    ## Creates { role1=[all_distinct_sizes...], role2=[all_distinct_sizes...] }
    sorted_sizes = {
        for role, hosts in local.role_grouped_hosts:
        (role) => reverse(sort(distinct([ for host in hosts: host.size_priority ])))
    }

    ## Groups hosts back into {role1=[{host}...], role2=[{host}...]}
    ## Hosts grouped by role are sorted by creation_time first -> size
    sorted_hosts = {
        for role, times in local.sorted_times: (role) => flatten([
            for time in times: [
                for size in local.sorted_sizes[role]:
                local.size_grouped_hosts[role][time][size]
                if lookup(local.size_grouped_hosts[role][time], size, "") != ""
            ]
        ])
    }

    ## To prevent noise in dns when adding/updating unrelated servers, we first check
    ##  keys/role in sorted_hosts. If none are available THEN check if any hosts
    ##  contain the role. It covers 95%+ of scenarios
    ## Reason being, sorting/aggregating based on resource data created at apply (time_static) causes anything
    ##  depending on that resource to not be known until apply. So if we aggregate build servers with web servers,
    ##  any change to build servers forces re-reads on web servers data. It does not know until apply if
    ##  the change ACTUALLY affects the web server order/data, forcing the re-read/update on apply.
    ## This is probably here to stay until something like giant public vs private clusters with no server roles
    ##  and launching containers/pods on either public/private cluster and all servers the same
    
    ## DNS will point to the oldest/largest server with the main role. If no main role, then a server containing that
    ##  role. Thus never pointing to newly created servers. Also immediately changes to the oldest server
    ##  that will still be active when scaling down, ensuring dns does not point to servers to be destroyed
    
    ## NEW WIP Issue-
    ## If the dns points to a server that is not the main role (ie admin+lead+db) then booting up a new fleet
    ##  with the main role (lead), the dns will choose the main role fleet first before its ready
    ## The most ideal thing we could find is "if y does not already exist do x over y and DO NOT depend/wait on y"
    ## The moment we attempt to use a var, it depends and waits on it. If we could detect if a resource/var exists before
    ##  attempting to access it and ignore it if it does not exist before apply, its all simpler

    ## Leaning towards an optional dns_priorty/weight attribute that allows user to overridde the default mechanism


    ## Any use cases beyond what this is doing, get static load balancer IP(s) and point to those
    dns_admin = (lookup(local.sorted_hosts, "admin", "") != "" ? local.sorted_hosts["admin"][0].ip
        : (length(local.sorted_admin) > 0 ? local.sorted_admin[0].ip : ""))

    dns_lead = (lookup(local.sorted_hosts, "lead", "") != "" ? local.sorted_hosts["lead"][0].ip
        : (length(local.sorted_lead) > 0 ? local.sorted_lead[0].ip : ""))

    dns_db = (lookup(local.sorted_hosts, "db", "") != "" ? local.sorted_hosts["db"][0].ip
        : (length(local.sorted_db) > 0 ? local.sorted_db[0].ip : ""))

    ## Specific sorted lists per role for dns
    sorted_admin = flatten([
        for role, hosts in local.sorted_hosts: [
            for HOST in hosts: HOST
            if contains(HOST.roles, "admin") && HOST.machine_id != ""
        ]
    ])
    sorted_lead = flatten([
        for role, hosts in local.sorted_hosts: [
            for HOST in hosts: HOST
            if contains(HOST.roles, "lead") && HOST.machine_id != ""
        ]
    ])
    sorted_db = flatten([
        for role, hosts in local.sorted_hosts: [
            for HOST in hosts: HOST
            if contains(HOST.roles, "db") && HOST.machine_id != ""
        ]
    ])
}

## dns
locals {
    cname_aliases = [
        for app in var.config.app_definitions:
        [app.subdomain_name, format("${app.subdomain_name}.db")]
        if app.create_dns_record == "true"
    ]
    cname_dev_aliases = [
        for app in var.config.app_definitions:
        [format("${app.subdomain_name}.beta"), format("${app.subdomain_name}.beta.db")]
        if app.create_dev_dns == "true"
    ]
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

## vpc for aws_instance
locals {
    consul = "CN-${var.config.packer_config.consul_version}"
    docker = "DK-${var.config.packer_config.docker_version}"
    dockerc = "DKC-${var.config.packer_config.docker_compose_version}"
    gitlab = "GL-${var.config.packer_config.gitlab_version}"
    redis = "R-${var.config.packer_config.redis_version}"
    large_image_name = uuidv5("dns", "${local.consul}_${local.docker}_${local.dockerc}_${local.gitlab}_${local.redis}")
    small_image_name = uuidv5("dns", "${local.consul}_${local.docker}_${local.dockerc}_${local.redis}")

    image_alias = {
        "admin" = "large"
        "lead" = "small"
        "db" = "small"
        "build" = "small"
    }
    ##NOTE: image_size is packer ami size, not instance size
    packer_images = {
        "large" = {
            "name" = local.large_image_name,
            "size" = "t3a.medium"
        }
        "small" = {
            "name" = local.small_image_name,
            "size" = "t3a.micro"
        }
    }
}

provider "aws" {
    region = var.config.aws_region

    # profile = "${var.profile}"
    access_key = var.config.aws_access_key
    secret_key = var.config.aws_secret_key
}
