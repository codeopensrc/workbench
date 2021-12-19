## TODO: Probably switch to azure firewall over security groups to limit sg_associations
resource "azurerm_network_security_group" "db_ports" {
    name                = "${local.vpc_name}_db-sg"
    location            = azurerm_resource_group.main.location
    resource_group_name = azurerm_resource_group.main.name

    security_rule {
        name                       = "postgresql"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "5432"
        source_address_prefix      = var.config.cidr_block
        destination_address_prefix = "*"
        ## TODO: Determine correct prefix for our use case
        #destination_address_prefix = azurerm_subnet.public_subnet.address_prefix
        #destination_address_prefix = azurerm_network_interface.main.private_ip_address
    }
    security_rule {
        name                       = "redis"
        priority                   = 1002
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "6379"
        source_address_prefix      = var.config.cidr_block
        destination_address_prefix = "*"
    }
    security_rule {
        name                       = "mongo"
        priority                   = 1003
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "27017"
        source_address_prefix      = var.config.cidr_block
        destination_address_prefix = "*"
    }

    lifecycle {
        create_before_destroy = true
    }
}


resource "azurerm_network_security_group" "app_ports" {
    name                = "${local.vpc_name}_app-sg"
    location            = azurerm_resource_group.main.location
    resource_group_name = azurerm_resource_group.main.name

    security_rule {
        name                       = "http(s)"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_ranges    = ["80", "443"]
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
    security_rule {
        name                       = "http(s)_internal"
        priority                   = 1002
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_ranges    = ["8085", "4433"]
        source_address_prefix      = var.config.cidr_block
        destination_address_prefix = "*"
    }

    # App/Api
    security_rule {
        name                       = "Docker swarm TCP"
        priority                   = 1003
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_ranges    = ["2377", "7946"]
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
    security_rule {
        name                       = "Docker swarm UDP"
        priority                   = 1004
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Udp"
        source_port_range          = "*"
        destination_port_ranges    = ["4789", "7946"]
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
    security_rule {
        name                       = "Docker bridge"
        priority                   = 1005
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "172.16.0.0/12"
        destination_address_prefix = "*"
    }

    security_rule {
        name                       = "Kubernetes"
        priority                   = 1006
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_ranges    = ["30000-32767", "6443", "2379-2380", "10250-10252"]
        source_address_prefix      = var.config.cidr_block
        destination_address_prefix = "*"
    }

    # STUN
    dynamic "security_rule" {
        for_each = {
            for key, value in var.stun_protos:
            key => value
            if var.config.stun_port != ""
        }
        content {
            name                       = "Stun: ${security_rule.value}"
            priority                   = 1007
            direction                  = "Inbound"
            access                     = "Allow"
            protocol                   = security_rule.value
            source_port_range          = "*"
            destination_port_range     = var.config.stun_port
            source_address_prefix      = "*"
            destination_address_prefix = "*"
        }
    }

    lifecycle {
        create_before_destroy = true
    }
}


resource "azurerm_network_security_group" "admin_ports" {
    name                = "${local.vpc_name}_admin-sg"
    location            = azurerm_resource_group.main.location
    resource_group_name = azurerm_resource_group.main.name

    security_rule {
        name                       = "http(s)"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_ranges    = ["80", "443", "7080"]
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
    security_rule {
        name                       = "Loki"
        priority                   = 1002
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "3100"
        source_address_prefix      = var.config.cidr_block
        destination_address_prefix = "*"
    }
    security_rule {
        name                       = "Kubernetes"
        priority                   = 1003
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_ranges    = ["6443", "2379-2380", "10250-10252"]
        source_address_prefix      = var.config.cidr_block
        destination_address_prefix = "*"
    }

    lifecycle {
        create_before_destroy = true
    }
}


resource "azurerm_network_security_group" "default_ports" {
    name                = "${local.vpc_name}_default-sg"
    location            = azurerm_resource_group.main.location
    resource_group_name = azurerm_resource_group.main.name

    security_rule {
        name                       = "SSH"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
    security_rule {
        name                       = "localhost"
        description                = "localhost ranges"
        priority                   = 1002
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefixes    = ["127.0.0.0/20", "192.168.0.0/20"]
        destination_address_prefix = "*"
    }

    # Default allow terraform user to every port
    security_rule {
        name                       = "All User"
        priority                   = 1003
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "${var.config.docker_machine_ip}/32"
        destination_address_prefix = "*"
    }

    # Consul communication between vpc
    security_rule {
        name                       = "consul"
        description                = "consul port ranges"
        priority                   = 1004
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_ranges    = ["8300-8302", "8400", "8500", "8600"]
        source_address_prefix      = var.config.cidr_block
        destination_address_prefix = "*"
    }
    security_rule {
        name                       = "consuludp1"
        priority                   = 1005
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Udp"
        source_port_range          = "*"
        destination_port_range     = "8300-8302"
        source_address_prefix      = var.config.cidr_block
        destination_address_prefix = "*"
    }

    #System metrics
    security_rule {
        name                       = "prometheus"
        priority                   = 1006
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "9100"
        source_address_prefix      = var.config.cidr_block
        destination_address_prefix = "*"
    }

    #kubernetes
    security_rule {
        name                       = "Kubernetes api"
        priority                   = 1007
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "10250"
        source_address_prefix      = var.config.cidr_block
        destination_address_prefix = "*"
    }
    security_rule {
        name                       = "Kubernetes flannel CNI"
        priority                   = 1008
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Udp"
        source_port_range          = "*"
        destination_port_range     = "8472"
        source_address_prefix      = var.config.cidr_block
        destination_address_prefix = "*"
    }

    ## NOTE: Untested - ICMP for network/ping
    security_rule {
        name                       = "Ping inbound"
        priority                   = 1009
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Icmp"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
    security_rule {
        name                       = "Ping outbound"
        priority                   = 1010
        direction                  = "Outbound"
        access                     = "Allow"
        protocol                   = "Icmp"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }


    security_rule {
        name                       = "All traffic out"
        priority                   = 1011
        direction                  = "Outbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    lifecycle {
        create_before_destroy = true
    }
}

resource "azurerm_network_security_group" "ext_db" {
    name                = "${local.vpc_name}_ext-db-sg"
    location            = azurerm_resource_group.main.location
    resource_group_name = azurerm_resource_group.main.name

    security_rule {
        name                       = "postgresql"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "5432"
        source_address_prefixes    = [
            for OBJ in var.config.app_ips:
            "${OBJ.ip}/32"
        ]
        destination_address_prefix = "*"
    }
    security_rule {
        name                       = "redis"
        priority                   = 1002
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "6379"
        source_address_prefixes    = [
            for OBJ in var.config.app_ips:
            "${OBJ.ip}/32"
        ]
        destination_address_prefix = "*"
    }
    security_rule {
        name                       = "mongo"
        priority                   = 1003
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "27017"
        source_address_prefixes    = [
            for OBJ in var.config.app_ips:
            "${OBJ.ip}/32"
        ]
        destination_address_prefix = "*"
    }

    lifecycle {
        create_before_destroy = true
    }
}

resource "azurerm_network_security_group" "ext_remote" {
    name                = "${local.vpc_name}_ext-remote-sg"
    location            = azurerm_resource_group.main.location
    resource_group_name = azurerm_resource_group.main.name

    security_rule {
        name                       = "All"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefixes    = [
            for OBJ in var.config.station_ips:
            "${OBJ.ip}/32"
        ]
        destination_address_prefix = "*"
    }

    lifecycle {
        create_before_destroy = true
    }
}



## TODO: Make sure only for db role servers
resource "azurerm_network_interface_security_group_association" "db_ports" {
    for_each = {
        for ind, cfg in local.cfg_servers:
        cfg.key => { cfg = cfg, ind = ind, role = cfg.role }
        if contains(cfg.roles, "db")
    }
    network_interface_id      = azurerm_network_interface.main[each.key].id
    network_security_group_id = azurerm_network_security_group.db_ports.id
}
## TODO: Make sure only for lead role servers
resource "azurerm_network_interface_security_group_association" "app_ports" {
    for_each = {
        for ind, cfg in local.cfg_servers:
        cfg.key => { cfg = cfg, ind = ind, role = cfg.role }
        if contains(cfg.roles, "lead")
    }
    network_interface_id      = azurerm_network_interface.main[each.key].id
    network_security_group_id = azurerm_network_security_group.app_ports.id
}

## TODO: Make sure only for admin role servers
resource "azurerm_network_interface_security_group_association" "admin_ports" {
    for_each = {
        for ind, cfg in local.cfg_servers:
        cfg.key => { cfg = cfg, ind = ind, role = cfg.role }
        if contains(cfg.roles, "admin")
    }
    network_interface_id      = azurerm_network_interface.main[each.key].id
    network_security_group_id = azurerm_network_security_group.admin_ports.id
}
resource "azurerm_network_interface_security_group_association" "default_ports" {
    for_each = {
        for ind, cfg in local.cfg_servers:
        cfg.key => { cfg = cfg, ind = ind, role = cfg.role }
    }
    network_interface_id      = azurerm_network_interface.main[each.key].id
    network_security_group_id = azurerm_network_security_group.default_ports.id
}
resource "azurerm_network_interface_security_group_association" "ext_db" {
    for_each = {
        for ind, cfg in local.cfg_servers:
        cfg.key => { cfg = cfg, ind = ind, role = cfg.role }
        if contains(cfg.roles, "db")
    }
    network_interface_id      = azurerm_network_interface.main[each.key].id
    network_security_group_id = azurerm_network_security_group.ext_db.id
}
resource "azurerm_network_interface_security_group_association" "ext_remote" {
    for_each = {
        for ind, cfg in local.cfg_servers:
        cfg.key => { cfg = cfg, ind = ind, role = cfg.role }
    }
    network_interface_id      = azurerm_network_interface.main[each.key].id
    network_security_group_id = azurerm_network_security_group.ext_remote.id
}



#resource "azurerm_firewall" "example" {
#    name                = "testfirewall"
#    location            = azurerm_resource_group.main.location
#    resource_group_name = azurerm_resource_group.main.name
#
#    ip_configuration {
#        name                 = "configuration"
#        subnet_id            = azurerm_subnet.example.id
#        public_ip_address_id = azurerm_public_ip.example.id
#    }
#}
