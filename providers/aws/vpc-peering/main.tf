terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws.peer]
    }
  }
}

locals {
  prefix = "${var.environment}-peering"
}

# VPC Peering Connection
resource "aws_vpc_peering_connection" "peer" {
  vpc_id        = var.requester_vpc_id
  peer_vpc_id   = var.peer_vpc_id
  peer_region   = var.peer_region
  peer_owner_id = var.peer_owner_id

  tags = merge(var.standard_tags, {
    Name        = "${var.environment}-vpc-peering"
    Environment = var.environment
  })
}

resource "aws_vpc_peering_connection_accepter" "peer" {
  provider              = aws.peer
  vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
  auto_accept           = true

  tags = merge(var.standard_tags, {
    Name        = "${var.environment}-vpc-peering-accepter"
    Environment = var.environment
  })
}

resource "aws_route" "requester_to_peer" {
  route_table_id         = var.requester_route_table_id
  destination_cidr_block = var.peer_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
}

resource "aws_route" "peer_to_requester" {
  provider               = aws.peer
  route_table_id         = var.peer_route_table_id
  destination_cidr_block = var.requester_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.peer.id
}
