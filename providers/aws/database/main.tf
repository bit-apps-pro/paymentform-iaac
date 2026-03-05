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

# Separate data volume for PostgreSQL (allows resizing)
resource "aws_ebs_volume" "primary_data" {
  availability_zone = var.availability_zone
  size              = var.primary_data_volume_size
  type              = var.volume_type
  encrypted         = true

  lifecycle {
    prevent_destroy = false
  }

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.prefix}-postgresql-data"
    }
  )
}

resource "aws_volume_attachment" "primary_data_attachment" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.primary_data.id
  instance_id = aws_instance.postgresql_primary.id
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

  depends_on = [aws_volume_attachment.primary_data_attachment]
}

# Separate data volume for PostgreSQL Replica
resource "aws_ebs_volume" "replica_data" {
  count             = var.enable_replica ? 1 : 0
  availability_zone = var.replica_availability_zone
  size              = var.replica_data_volume_size
  type              = var.volume_type
  encrypted         = true

  lifecycle {
    prevent_destroy = false
  }

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.prefix}-postgresql-replica-data"
    }
  )
}

resource "aws_volume_attachment" "replica_data_attachment" {
  count    = var.enable_replica ? 1 : 0
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.replica_data[0].id
  instance_id = aws_instance.postgresql_replica[0].id
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

  depends_on = [aws_volume_attachment.replica_data_attachment]
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

# Cross-region Replica Data Volume
resource "aws_ebs_volume" "cross_region_data" {
  count                = var.enable_cross_region_replica ? 1 : 0
  availability_zone   = var.cross_region_availability_zone
  size                = var.replica_data_volume_size
  type                = var.volume_type
  encrypted           = true

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.prefix}-postgresql-cross-region-data"
    }
  )
}

resource "aws_volume_attachment" "cross_region_data_attachment" {
  count       = var.enable_cross_region_replica ? 1 : 0
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.cross_region_data[0].id
  instance_id = aws_instance.postgresql_cross_region_replica[0].id
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
