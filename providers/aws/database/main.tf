terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  prefix = var.environment

  # Build volume configurations dynamically from var.volumes
  volumes = { for idx, vol in var.volumes : vol.name => vol }

  # Determine if we should create volumes or use pre-created ones
  use_external_volumes = length(var.volume_ids) > 0
}

# EIP for PostgreSQL Primary (stable IP for failover)
resource "aws_eip" "primary" {
  count  = var.assign_eip ? 1 : 0
  domain = "vpc"

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.prefix}-postgresql-primary-eip"
    }
  )
}

# EIP Association for Primary
resource "aws_eip_association" "primary" {
  count         = var.assign_eip ? 1 : 0
  instance_id   = aws_instance.postgresql_primary.id
  allocation_id = aws_eip.primary[0].id
}

# Dynamic volume creation (only if volume_ids not provided)
module "volumes" {
  source = "../../volume"

  for_each = local.use_external_volumes ? {} : local.volumes

  environment        = var.environment
  name               = each.value.name
  availability_zone  = each.value.availability_zone
  size               = each.value.size
  volume_type        = each.value.volume_type
  encrypted          = each.value.encrypted
  iops               = each.value.iops
  throughput         = each.value.throughput
  device_name        = each.value.device_name
  instance_id        = ""
  standard_tags      = var.standard_tags
  prevent_destroy    = each.value.prevent_destroy
}

# Volume attachments - primary data volume
resource "aws_volume_attachment" "primary_data" {
  count    = try(length([for v in var.volumes : v if v.name == "postgresql-primary-data"]), 0) > 0 || lookup(var.volume_ids, "postgresql-primary-data", "") != "" ? 1 : 0
  device_name = "/dev/sdf"
  volume_id   = local.use_external_volumes ? var.volume_ids["postgresql-primary-data"] : module.volumes["postgresql-primary-data"].volume_id
  instance_id = aws_instance.postgresql_primary.id
}

# Volume attachments - replica data volume
resource "aws_volume_attachment" "replica_data" {
  count    = var.enable_replica ? (try(length([for v in var.volumes : v if v.name == "postgresql-replica-data"]), 0) > 0 || lookup(var.volume_ids, "postgresql-replica-data", "") != "" ? 1 : 0) : 0
  device_name = "/dev/sdf"
  volume_id   = local.use_external_volumes ? var.volume_ids["postgresql-replica-data"] : module.volumes["postgresql-replica-data"].volume_id
  instance_id = aws_instance.postgresql_replica[0].id
}

# EC2 Instance for PostgreSQL Primary
resource "aws_instance" "postgresql_primary" {
  ami           = var.ami_id
  instance_type = var.primary_instance_type
  subnet_id     = var.subnet_ids[0]

  disable_api_termination = true

  vpc_security_group_ids = [
    var.security_group_id
  ]

  iam_instance_profile = aws_iam_instance_profile.pgbackrest_profile.name

  root_block_device {
    volume_size = var.primary_volume_size
    volume_type = var.volume_type
    encrypted   = true
  }

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.prefix}-postgresql-primary"
      Role = "postgresql-primary"
    }
  )

  user_data = base64encode(templatefile("${path.module}/userdata-primary.sh", {
    environment            = var.environment
    postgres_version       = var.postgres_version
    db_name                = var.db_name
    db_user                = var.db_user
    db_password            = var.db_password
    r2_endpoint            = var.r2_endpoint
    r2_bucket_name         = var.r2_bucket_name
    r2_access_key          = var.r2_access_key
    r2_secret_key          = var.r2_secret_key
    pgbackrest_cipher_pass = var.pgbackrest_cipher_pass
    region                 = var.region
    data_volume_device     = "/dev/sdf"
  }))

  depends_on = [aws_volume_attachment.primary_data]
}

# EC2 Instance for PostgreSQL Replica
resource "aws_instance" "postgresql_replica" {
  count         = var.enable_replica ? 1 : 0
  ami           = var.ami_id
  instance_type = var.replica_instance_type
  subnet_id     = length(var.subnet_ids) > 1 ? var.subnet_ids[1] : var.subnet_ids[0]

  disable_api_termination = true

  vpc_security_group_ids = [
    var.security_group_id
  ]

  root_block_device {
    volume_size = var.replica_volume_size
    volume_type = var.volume_type
    encrypted   = true
  }

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.prefix}-postgresql-replica"
      Role = "postgresql-replica"
    }
  )

  user_data = base64encode(templatefile("${path.module}/userdata-replica.sh", {
    environment         = var.environment
    postgres_version    = var.postgres_version
    primary_ip          = aws_instance.postgresql_primary.private_ip
    db_user             = var.db_user
    db_password         = var.db_password
    data_volume_device  = "/dev/sdf"
  }))

  depends_on = [aws_instance.postgresql_primary, aws_volume_attachment.replica_data]
}

# IAM Role for EC2 to access S3/R2 for pgbackrest
resource "aws_iam_role" "pgbackrest_role" {
  name = "${local.prefix}-pgbackrest-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "pgbackrest_profile" {
  name = "${local.prefix}-pgbackrest-profile"
  role = aws_iam_role.pgbackrest_role.name
}

# Policy for S3/R2 access for pgbackrest
resource "aws_iam_policy" "pgbackrest_s3_access" {
  name = "${local.prefix}-pgbackrest-s3-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = "arn:aws:s3:::${var.r2_bucket_name}"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::${var.r2_bucket_name}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "pgbackrest_s3_attachment" {
  role       = aws_iam_role.pgbackrest_role.name
  policy_arn = aws_iam_policy.pgbackrest_s3_access.arn
}

# Cross-region Read Replica
resource "aws_instance" "postgresql_cross_region_replica" {
  count                = var.enable_cross_region_replica ? 1 : 0
  ami                  = var.ami_id
  instance_type        = var.replica_instance_type
  subnet_id            = var.replica_subnet_ids[0]

  vpc_security_group_ids = [
    var.security_group_id
  ]

  root_block_device {
    volume_size = var.replica_volume_size
    volume_type = var.volume_type
    encrypted   = true
  }

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.prefix}-postgresql-cross-region-replica"
      Role = "postgresql-replica-cross-region"
    }
  )

  user_data = base64encode(templatefile("${path.module}/userdata-replica.sh", {
    environment         = var.environment
    postgres_version    = var.postgres_version
    primary_ip          = aws_instance.postgresql_primary.private_ip
    db_user             = var.db_user
    db_password         = var.db_password
    data_volume_device  = "/dev/sdf"
  }))

  depends_on = [aws_instance.postgresql_primary]
}

# Outputs
output "primary_instance_id" {
  value = aws_instance.postgresql_primary.id
}

output "replica_instance_id" {
  value = aws_instance.postgresql_replica[*].id
}

output "volume_ids" {
  value = local.use_external_volumes ? var.volume_ids : { for k, v in module.volumes : k => v.volume_id }
}
