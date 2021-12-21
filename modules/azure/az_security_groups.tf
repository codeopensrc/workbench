resource "azurerm_network_security_group" "main" {
    for_each = {
        for ind, cfg in local.cfg_servers: cfg.key => cfg.key
    }
    name                = "${local.vpc_name}_${each.key}_sg"
    location            = azurerm_resource_group.main.location
    resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_network_interface_security_group_association" "main" {
    for_each = {
        for ind, cfg in local.cfg_servers: cfg.key => cfg.key
    }
    network_interface_id      = azurerm_network_interface.main[each.key].id
    network_security_group_id = azurerm_network_security_group.main[each.key].id
}

resource "azurerm_subnet_network_security_group_association" "pubsubnet" {
    subnet_id                 = azurerm_subnet.pubsubnet.id
    network_security_group_id = azurerm_network_security_group.pubsubnet.id
}

####### ALL #######
resource "azurerm_network_security_rule" "allow_ips" {
    for_each = {
        for ind, cfg in local.cfg_servers: cfg.key => cfg.key
    }
    name                       = "allow_ips"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = flatten([
        "${var.config.docker_machine_ip}/32",                 ## workstation
        [for OBJ in var.config.station_ips: "${OBJ.ip}/32"],  ## extra stations
        "127.0.0.0/20", "192.168.0.0/20"                      ## localhost ranges
    ])
    destination_address_prefix = "*"
    ## TODO: Determine correct prefix(es) for our use case(s)
    #destination_address_prefix = azurerm_subnet.public_subnet.address_prefix
    #destination_address_prefix = azurerm_network_interface.main.private_ip_address
    resource_group_name         = azurerm_resource_group.main.name
    network_security_group_name = azurerm_network_security_group.main[each.key].name
}
resource "azurerm_network_security_rule" "ping_in" {
    for_each = {
        for ind, cfg in local.cfg_servers: cfg.key => cfg.key
    }
    name                       = "ping_in"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    resource_group_name         = azurerm_resource_group.main.name
    network_security_group_name = azurerm_network_security_group.main[each.key].name
}
resource "azurerm_network_security_rule" "ssh" {
    for_each = {
        for ind, cfg in local.cfg_servers: cfg.key => cfg.key
    }
    name                       = "SSH"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    resource_group_name         = azurerm_resource_group.main.name
    network_security_group_name = azurerm_network_security_group.main[each.key].name
}

resource "azurerm_network_security_rule" "vpc_internal_tcp" {
    for_each = {
        for ind, cfg in local.cfg_servers: cfg.key => cfg.key
    }
    name                       = "vpc_internal_tcp"
    priority                   = 103
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = [
        "9100",                ## prometheus
        "8300-8302", "8400",   ## consul
        "8500", "8600",        ## consul
        "10250",               ## kubernetes kubelet
    ]
    source_address_prefix      = var.config.cidr_block
    destination_address_prefix = "*"
    resource_group_name         = azurerm_resource_group.main.name
    network_security_group_name = azurerm_network_security_group.main[each.key].name
}
resource "azurerm_network_security_rule" "vpc_internal_udp" {
    for_each = {
        for ind, cfg in local.cfg_servers: cfg.key => cfg.key
    }
    name                       = "vpc_internal_udp"
    priority                   = 104
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_ranges    = [
        "8300-8302",           ## consul
        "8472"                 ## kubernetes flannel CNI
    ]
    source_address_prefix      = var.config.cidr_block
    destination_address_prefix = "*"
    resource_group_name         = azurerm_resource_group.main.name
    network_security_group_name = azurerm_network_security_group.main[each.key].name
}



####### DB #######
resource "azurerm_network_security_rule" "db" {
    for_each = {
        for ind, cfg in local.cfg_servers: cfg.key => cfg.key
        if contains(cfg.roles, "db")
    }
    name                       = "db"
    priority                   = 201
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = [
        "5432",                ## postgres
        "6379",                ## redis
        "27017",               ## mongo
    ]
    source_address_prefixes    = flatten([
        var.config.cidr_block,
        [for OBJ in var.config.app_ips: "${OBJ.ip}/32"]
    ])
    destination_address_prefix = "*"
    resource_group_name         = azurerm_resource_group.main.name
    network_security_group_name = azurerm_network_security_group.main[each.key].name
}


####### APP #######
resource "azurerm_network_security_rule" "app_tcp" {
    for_each = {
        for ind, cfg in local.cfg_servers: cfg.key => cfg.key
        if contains(cfg.roles, "lead")
    }
    name                       = "app_tcp"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = [
        "80", "443",           ## http
        "2377", "7946",        ## docker_swarm_tcp
        var.config.stun_port,  ## stun
    ]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    resource_group_name         = azurerm_resource_group.main.name
    network_security_group_name = azurerm_network_security_group.main[each.key].name
}
resource "azurerm_network_security_rule" "app_internal" {
    for_each = {
        for ind, cfg in local.cfg_servers: cfg.key => cfg.key
        if contains(cfg.roles, "lead")
    }
    name                       = "app_internal"
    priority                   = 301
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = [
        "8085", "4433",        ## http(s)
        "30000-32767",         ## kubernetes nodeport
        "6443",                ## kubernetes api
        "2379-2380",           ## kubernetes etcd
        "10250-10252"          ## kubernetes control-plane containers
    ]
    source_address_prefix      = var.config.cidr_block
    destination_address_prefix = "*"
    resource_group_name         = azurerm_resource_group.main.name
    network_security_group_name = azurerm_network_security_group.main[each.key].name
}
resource "azurerm_network_security_rule" "app_udp" {
    for_each = {
        for ind, cfg in local.cfg_servers: cfg.key => cfg.key
        if contains(cfg.roles, "lead")
    }
    name                       = "app_udp"
    priority                   = 303
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_ranges    = [
        "4789", "7946",        ## docker_swarm_udp
        var.config.stun_port   ## stun
    ]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    resource_group_name         = azurerm_resource_group.main.name
    network_security_group_name = azurerm_network_security_group.main[each.key].name
}
resource "azurerm_network_security_rule" "docker_bridge" {
    for_each = {
        for ind, cfg in local.cfg_servers: cfg.key => cfg.key
        if contains(cfg.roles, "lead")
    }
    name                       = "docker_bridge"
    priority                   = 304
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "172.16.0.0/12"
    destination_address_prefix = "*"
    resource_group_name         = azurerm_resource_group.main.name
    network_security_group_name = azurerm_network_security_group.main[each.key].name
}



####### ADMIN #######
#### TODO: Better conditionals if we do not have admin - see other cloud security groups
resource "azurerm_network_security_rule" "letsencrypt" {
    for_each = {
        for ind, cfg in local.cfg_servers: cfg.key => cfg.key
        if contains(cfg.roles, "admin")
    }
    name                       = "letsencrypt"
    priority                   = 400
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "7080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    resource_group_name         = azurerm_resource_group.main.name
    network_security_group_name = azurerm_network_security_group.main[each.key].name
}
resource "azurerm_network_security_rule" "admin_internal" {
    for_each = {
        for ind, cfg in local.cfg_servers: cfg.key => cfg.key
        if contains(cfg.roles, "admin")
    }
    name                       = "admin_internal"
    priority                   = 401
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = [
        "3100",                ## loki
        "6443",                ## kubernetes api
        "2379-2380",           ## kubernetes etcd
        "10250-10252"          ## kubernetes control-plane containers
    ]
    source_address_prefix      = var.config.cidr_block
    destination_address_prefix = "*"
    resource_group_name         = azurerm_resource_group.main.name
    network_security_group_name = azurerm_network_security_group.main[each.key].name
}


resource "azurerm_network_security_group" "pubsubnet" {
    name                = "${local.vpc_name}_pubsubnet"
    location            = azurerm_resource_group.main.location
    resource_group_name = azurerm_resource_group.main.name

    security_rule {
        name                       = "stations"
        priority                   = 1000
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefixes    = flatten([
            "${var.config.docker_machine_ip}/32",
            [for OBJ in var.config.station_ips: "${OBJ.ip}/32"]
        ])
        destination_address_prefix = "*"
    }
    security_rule {
        name                       = "ping_in"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Icmp"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
    security_rule {
        name                       = "public_tcp"
        priority                   = 1002
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_ranges    = [
            "22",                  ## ssh
            "80", "443",           ## http
            "2377", "7946",        ## docker_swarm_tcp
            var.config.stun_port,  ## stun
            "7080",                ## letsencrypt
        ]
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
    security_rule {
        name                       = "public_udp"
        priority                   = 1003
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Udp"
        source_port_range          = "*"
        destination_port_ranges    = [
            "4789", "7946",        ## docker_swarm_udp
            var.config.stun_port   ## stun
        ]
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    lifecycle {
        create_before_destroy = true
    }
}
