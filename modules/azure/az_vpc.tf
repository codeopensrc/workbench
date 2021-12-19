locals {
    vpc_name = "${var.config.server_name_prefix}-vpc"
}

resource "azurerm_virtual_network" "terraform_vpc" {
    name                = local.vpc_name
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    address_space       = [ var.config.cidr_block ]
}

resource "azurerm_subnet" "public_subnet" {
    name                 = "public-subnet_${local.vpc_name}"
    resource_group_name  = azurerm_resource_group.main.name
    virtual_network_name = azurerm_virtual_network.terraform_vpc.name
    address_prefixes       = [ cidrsubnet(var.config.cidr_block, 8, 2) ]
}

resource "azurerm_public_ip" "main" {
    name                = "pub-ip_${local.vpc_name}"
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "main" {
    for_each = {
        for ind, cfg in local.cfg_servers:
        cfg.key => { cfg = cfg, ind = ind, role = cfg.role }
    }
    name                = "pub-NIC-${each.key}_${local.vpc_name}"
    location            = azurerm_resource_group.main.location
    resource_group_name = azurerm_resource_group.main.name

    ip_configuration {
        name                          = "pub-NIC-config1_${local.vpc_name}"
        subnet_id                     = azurerm_subnet.public_subnet.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.main.id
    }
}



## TODO: Routing table logic
## According to:
##  https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network_gateway
## Internet gateways take 30min-1hr to make so we're exploring different methods for now
## Mainly attempting to mimic our aws/aws_vpc.tf
## Have to go NIC + public ip for the time being

#resource "azurerm_route_table" "rtb" {
#    #name                = "example-routetable"
#    name                = "RTB_${local.vpc_name}"
#    location            = azurerm_resource_group.main.location
#    resource_group_name = azurerm_resource_group.main.name
#}
#resource "azurerm_subnet_route_table_association" "public_subnet_assoc" {
#    subnet_id      = azurerm_subnet.public_subnet.id
#    route_table_id = azurerm_route_table.rtb.id
#}
#resource "azurerm_route" "internet_access" {
#    #name                = "acceptanceTestRoute1"
#    name                = "IA-route_${local.vpc_name}"
#    resource_group_name = azurerm_resource_group.main.name
#    route_table_name    = azurerm_route_table.rtb.name
#    #address_prefix      = "10.1.0.0/16"
#    address_prefix      = "10.1.0.0/16"
#    next_hop_type       = "vnetlocal"
#}



#resource "azurerm_network_ddos_protection_plan" "main" {
#    #name                = "ddospplan1"
#    name                = "ddosplan_${local.vpc_name}"
#    location            = azurerm_resource_group.main.location
#    resource_group_name = azurerm_resource_group.main.name
#}
