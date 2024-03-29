locals {
    vpc_name = "${var.config.server_name_prefix}_vpc"
}

# query/create vpc
resource "aws_vpc" "terraform_vpc" {
    cidr_block           = var.config.cidr_block
    enable_dns_support   = true
    enable_dns_hostnames = true
    tags = {
        Name          = local.vpc_name
    }
}

# query/create igw
resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.terraform_vpc.id
    tags = {
        Name          = "IG_${local.vpc_name}"
    }
}

# query/create rtb
resource "aws_route_table" "rtb" {
    vpc_id = aws_vpc.terraform_vpc.id
    tags = {
        Name          = "RTB_${local.vpc_name}"
    }
}

# query/create subnets
resource "aws_subnet" "public_subnet" {
    vpc_id     = aws_vpc.terraform_vpc.id
    map_public_ip_on_launch = true
    cidr_block = cidrsubnet(aws_vpc.terraform_vpc.cidr_block, 8, 2)
    tags = {
        Name          = "subnet_${local.vpc_name}"
    }
}

# route
resource "aws_route" "internet_access" {
    route_table_id         = aws_route_table.rtb.id
    gateway_id             = aws_internet_gateway.igw.id
    destination_cidr_block = "0.0.0.0/0"
}

# route table association
resource "aws_route_table_association" "public_subnet_assoc" {
    subnet_id      = aws_subnet.public_subnet.id
    route_table_id = aws_route_table.rtb.id
}


# data "aws_route53_zone" "internal" {
#   name         = "vpc.internal."
#   private_zone = true
#   vpc_id       = "${var.vpc_id}"
# }
