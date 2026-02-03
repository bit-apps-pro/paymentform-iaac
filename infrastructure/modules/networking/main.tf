terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.environment}-vpc"
    }
  )
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.environment}-igw"
    }
  )
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_gateway" {
  domain = "vpc"

  depends_on = [
    aws_internet_gateway.main
  ]

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.environment}-nat-eip"
    }
  )
}

# NAT Gateway
resource "aws_nat_gateway" "main" {
  allocation_id     = aws_eip.nat_gateway.id
  subnet_id         = element(aws_subnet.public[*].id, 0) # Use first public subnet
  connectivity_type = "public"

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.environment}-nat-gateway"
    }
  )

  depends_on = [
    aws_internet_gateway.main
  ]
}

# Public Subnets (for ALB)
resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    var.standard_tags,
    {
      Name                     = "${var.environment}-public-subnet-${count.index + 1}"
      "kubernetes.io/role/elb" = "1"
    }
  )
}

# Private Subnets (for compute)
resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(
    var.standard_tags,
    {
      Name                              = "${var.environment}-private-subnet-${count.index + 1}"
      "kubernetes.io/role/internal-elb" = "1"
    }
  )
}

# Route table for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.environment}-public-route-table"
    }
  )
}

# Route for public route table (to internet gateway)
resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route table for private subnets
resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.environment}-private-route-table-${count.index + 1}"
    }
  )
}

# Route for private route table (to NAT gateway)
resource "aws_route" "private_nat_gateway" {
  count                  = length(var.availability_zones)
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

# Associate private subnets with private route tables
resource "aws_route_table_association" "private" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
