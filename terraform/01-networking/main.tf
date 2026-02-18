terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# VPC mit IPv6
resource "aws_vpc" "main" {
  cidr_block                       = var.vpc_cidr
  assign_generated_ipv6_cidr_block = true
  enable_dns_hostnames             = true
  enable_dns_support               = true

  tags = {
    Name        = "${var.project_prefix}-vpc-${var.region}-1"
    Environment = var.environment
    Project     = var.project_prefix
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_prefix}-igw-${var.region}"
    Environment = var.environment
    Project     = var.project_prefix
  }
}

# Egress-Only Internet Gateway
resource "aws_egress_only_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_prefix}-eigw-${var.region}"
    Environment = var.environment
    Project     = var.project_prefix
  }
}

# Public Subnets mit IPv6
resource "aws_subnet" "public" {
  count                           = length(var.availability_zones)
  vpc_id                          = aws_vpc.main.id
  cidr_block                      = var.public_subnet_cidrs[count.index]
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, count.index)
  availability_zone               = var.availability_zones[count.index]
  map_public_ip_on_launch         = true
  assign_ipv6_address_on_creation = true

  tags = {
    Name        = "${var.project_prefix}-public-subnet-${var.availability_zones[count.index]}"
    Environment = var.environment
    Project     = var.project_prefix
    Type        = "public"
  }
}

# Private Subnets mit IPv6
resource "aws_subnet" "private" {
  count                           = length(var.availability_zones)
  vpc_id                          = aws_vpc.main.id
  cidr_block                      = var.private_subnet_cidrs[count.index]
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, count.index + 10)
  availability_zone               = var.availability_zones[count.index]
  assign_ipv6_address_on_creation = true

  tags = {
    Name        = "${var.project_prefix}-private-subnet-${var.availability_zones[count.index]}"
    Environment = var.environment
    Project     = var.project_prefix
    Type        = "private"
  }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.project_prefix}-rt-public-${var.region}"
    Environment = var.environment
    Project     = var.project_prefix
    Type        = "public"
  }
}

# Private Route Table mit Egress-Only IGW
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    ipv6_cidr_block        = "::/0"
    egress_only_gateway_id = aws_egress_only_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.project_prefix}-rt-private-${var.region}"
    Environment = var.environment
    Project     = var.project_prefix
    Type        = "private"
  }
}

# Associate Public Subnets with Public Route Table
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Associate Private Subnets with Private Route Table
resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
