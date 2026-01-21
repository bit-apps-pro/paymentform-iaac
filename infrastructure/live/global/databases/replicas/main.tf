terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "paymentform-db-replica-state"
    key            = "databases/replicas/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "paymentform-terraform-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "paymentform"
      Environment = var.environment
      Component   = "database-replica"
      ManagedBy   = "terraform"
    }
  }
}

# VPC data source to get existing VPC
data "aws_vpc" "selected" {
  id = var.vpc_id
}

# Subnet IDs data source
data "aws_subnets" "selected" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
}

# Security group for database access
resource "aws_security_group" "database_replica" {
  name_prefix = "paymentform-db-replica"
  description = "Security group for replica database"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "paymentform-db-replica-sg"
    Environment = var.environment
  }
}

# Aurora PostgreSQL global cluster (for cross-region replication)
resource "aws_rds_global_cluster" "global" {
  count = var.enable_global_cluster ? 1 : 0

  global_cluster_identifier = var.global_cluster_identifier
  engine                    = "aurora-postgresql"
  database_name             = var.database_name
  storage_encrypted         = true

  tags = {
    Name        = var.global_cluster_identifier
    Environment = var.environment
  }
}

# Aurora PostgreSQL cluster for replica region
resource "aws_rds_cluster" "replica" {
  cluster_identifier            = var.cluster_identifier
  engine                        = "aurora-postgresql"
  engine_version                = var.engine_version
  database_name                 = var.database_name
  db_subnet_group_name          = aws_db_subnet_group.replica.name
  vpc_security_group_ids        = [aws_security_group.database_replica.id]
  skip_final_snapshot           = !var.create_final_snapshot
  deletion_protection           = var.deletion_protection
  storage_encrypted             = true
  replication_source_identifier = var.primary_cluster_arn
  engine_mode                   = "provisioned" # Global clusters require provisioned mode

  tags = {
    Name        = var.cluster_identifier
    Environment = var.environment
  }

  depends_on = [aws_rds_global_cluster.global]
}

# DB subnet group for replica
resource "aws_db_subnet_group" "replica" {
  name       = "${var.cluster_identifier}-subnets"
  subnet_ids = data.aws_subnets.selected.ids

  tags = {
    Name        = "${var.cluster_identifier}-subnets"
    Environment = var.environment
  }
}

# Replica instances
resource "aws_rds_cluster_instance" "replica" {
  count = var.replica_instances

  identifier         = "${var.cluster_identifier}-replica-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.replica.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.replica.engine
  engine_version     = aws_rds_cluster.replica.engine_version

  tags = {
    Name        = "${var.cluster_identifier}-replica-${count.index + 1}"
    Environment = var.environment
    Role        = "REPLICA"
  }
}

# Outputs
output "cluster_endpoint" {
  description = "Endpoint for the replica cluster"
  value       = aws_rds_cluster.replica.endpoint
}

output "cluster_reader_endpoint" {
  description = "Read-only endpoint for the replica cluster"
  value       = aws_rds_cluster.replica.reader_endpoint
}

output "cluster_connection_string" {
  description = "Complete connection string for the replica cluster"
  value       = "postgresql://${var.master_username}:${var.master_password}@${aws_rds_cluster.replica.endpoint}/${var.database_name}"
}

output "security_group_id" {
  description = "ID of the security group for the replica database"
  value       = aws_security_group.database_replica.id
}