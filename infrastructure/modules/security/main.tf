terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ALB Security Group - Allow HTTP/HTTPS from internet
resource "aws_security_group" "alb" {
  name_prefix = "${var.environment}-alb-sg"
  vpc_id      = var.vpc_id

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.environment}-alb-security-group"
    }
  )
}

# Inbound rules for ALB
resource "aws_security_group_rule" "alb_ingress_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTP from internet"
}

resource "aws_security_group_rule" "alb_ingress_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTPS from internet"
}

# Outbound rules for ALB
resource "aws_security_group_rule" "alb_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "Allow all outbound traffic"
}

# ECS Security Group - Allow traffic from ALB
resource "aws_security_group" "ecs" {
  name_prefix = "${var.environment}-ecs-sg"
  vpc_id      = var.vpc_id

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.environment}-ecs-security-group"
    }
  )
}

# Inbound rules for ECS - allow from ALB
resource "aws_security_group_rule" "ecs_ingress_from_alb" {
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 8000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs.id
  description              = "Allow traffic from ALB to ECS containers"
}

# Additional inbound rule for application ports
resource "aws_security_group_rule" "ecs_ingress_app_ports" {
  count                    = length(var.app_ports)
  type                     = "ingress"
  from_port                = var.app_ports[count.index]
  to_port                  = var.app_ports[count.index]
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs.id
  description              = "Allow traffic on app port ${var.app_ports[count.index]}"
}

# Outbound rules for ECS
resource "aws_security_group_rule" "ecs_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs.id
  description       = "Allow all outbound traffic"
}

# Database Security Group - Allow traffic from ECS
resource "aws_security_group" "database" {
  name_prefix = "${var.environment}-db-sg"
  vpc_id      = var.vpc_id

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.environment}-database-security-group"
    }
  )
}

# Inbound rules for database - allow from ECS
resource "aws_security_group_rule" "db_ingress_from_ecs" {
  type                     = "ingress"
  from_port                = 5432  # PostgreSQL
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs.id
  security_group_id        = aws_security_group.database.id
  description              = "Allow PostgreSQL traffic from ECS"
}

# Outbound rules for database
resource "aws_security_group_rule" "db_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.database.id
  description       = "Allow all outbound traffic"
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.environment}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.environment}-ecs-task-execution-role"
    }
  )
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM Role for ECS Tasks
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.environment}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.environment}-ecs-task-role"
    }
  )
}

# Policy for accessing Secrets Manager (Neon API key, Turso token)
resource "aws_iam_policy" "secrets_manager_access" {
  name        = "${var.environment}-secrets-manager-access-policy"
  description = "Policy for accessing secrets in Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          var.neon_api_key_secret_arn,
          var.turso_token_secret_arn
        ]
      }
    ]
  })
}

# Attach secrets manager policy to ECS task role
resource "aws_iam_role_policy_attachment" "secrets_manager_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.secrets_manager_access.arn
}

# Policy for CloudWatch logs
resource "aws_iam_policy" "cloudwatch_logs_access" {
  name        = "${var.environment}-cloudwatch-logs-access-policy"
  description = "Policy for writing logs to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Attach CloudWatch logs policy to ECS task execution role
resource "aws_iam_role_policy_attachment" "cloudwatch_logs_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.cloudwatch_logs_access.arn
}

# KMS Key for encryption (optional)
resource "aws_kms_key" "encryption_key" {
  description             = "KMS key for encrypting resources in ${var.environment}"
  deletion_window_in_days = 7

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.environment}-encryption-key"
    }
  )
}

resource "aws_kms_alias" "encryption_key_alias" {
  name          = "alias/${var.environment}-encryption-key"
  target_key_id = aws_kms_key.encryption_key.key_id
}