terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "paymentform-db-primary-state"
    key            = "databases/primary/terraform.tfstate"
    region         = "us-east-1"
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
      Component   = "database-primary"
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
resource "aws_security_group" "database" {
  name_prefix = "paymentform-db-primary"
  description = "Security group for primary database"
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
    Name        = "paymentform-db-primary-sg"
    Environment = var.environment
  }
}

# Aurora PostgreSQL cluster
resource "aws_rds_cluster" "primary" {
  cluster_identifier             = var.cluster_identifier
  engine                         = "aurora-postgresql"
  engine_version                 = var.engine_version
  database_name                  = var.database_name
  master_username                = var.master_username
  master_password                = var.master_password
  backup_retention_period        = var.backup_retention_period
  preferred_backup_window        = var.preferred_backup_window
  preferred_maintenance_window   = var.preferred_maintenance_window
  db_subnet_group_name           = aws_db_subnet_group.main.name
  vpc_security_group_ids         = [aws_security_group.database.id]
  skip_final_snapshot            = !var.create_final_snapshot
  deletion_protection            = var.deletion_protection
  storage_encrypted              = true
  enable_global_write_forwarding = true # Enable write forwarding for global clusters

  serverlessv2_scaling_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  tags = {
    Name        = var.cluster_identifier
    Environment = var.environment
  }
}

# DB subnet group
resource "aws_db_subnet_group" "main" {
  name       = "${var.cluster_identifier}-subnets"
  subnet_ids = data.aws_subnets.selected.ids

  tags = {
    Name        = "${var.cluster_identifier}-subnets"
    Environment = var.environment
  }
}

# Primary instance
resource "aws_rds_cluster_instance" "primary" {
  count = var.primary_instances

  identifier         = "${var.cluster_identifier}-primary-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.primary.engine
  engine_version     = aws_rds_cluster.primary.engine_version

  tags = {
    Name        = "${var.cluster_identifier}-primary-${count.index + 1}"
    Environment = var.environment
    Role        = "PRIMARY"
  }
}

# Outputs
output "cluster_endpoint" {
  description = "Write endpoint for the cluster"
  value       = aws_rds_cluster.primary.endpoint
}

output "cluster_reader_endpoint" {
  description = "Read-only endpoint for the cluster"
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "cluster_connection_string" {
  description = "Complete connection string for the cluster"
  value       = "postgresql://${var.master_username}:${var.master_password}@${aws_rds_cluster.primary.endpoint}/${var.database_name}"
}

output "security_group_id" {
  description = "ID of the security group for the database"
  value       = aws_security_group.database.id
}