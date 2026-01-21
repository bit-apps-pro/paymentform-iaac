terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "paymentform-client-state"
    key            = "client/terraform.tfstate"
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
      Component   = "client"
      ManagedBy   = "terraform"
    }
  }
}

# VPC for client services
module "vpc" {
  source = "../../modules/vpc"

  name                 = "client-vpc"
  cidr_block           = var.vpc_cidr
  az_count             = length(var.availability_zones)
  environment          = var.environment
  enable_nat_gateway   = true
  single_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# ECS cluster for client services
resource "aws_ecs_cluster" "client" {
  name = "paymentform-client-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Client task definition
resource "aws_ecs_task_definition" "client" {
  family                   = "paymentform-client"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.client_cpu
  memory                   = var.client_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.client_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "client"
      image = "${var.client_image}:${var.client_version}"

      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "NEXT_PUBLIC_API_URL", value = var.api_url },
        { name = "NEXT_PUBLIC_DOMAIN", value = var.frontend_domain },
        { name = "NODE_ENV", value = var.environment }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.client.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

# Client service
resource "aws_ecs_service" "client" {
  name            = "paymentform-client-service"
  cluster         = aws_ecs_cluster.client.id
  task_definition = aws_ecs_task_definition.client.arn
  desired_count   = var.client_instance_count
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.client.id]
    subnets          = module.vpc.private_subnets
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.client.arn
    container_name   = "client"
    container_port   = 3000
  }

  depends_on = [
    aws_lb_listener.client,
    aws_iam_role_policy_attachment.ecs_execution_role_policy
  ]
}

# Application Load Balancer
resource "aws_lb" "client" {
  name               = "paymentform-client-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets
}

# ALB Listener
resource "aws_lb_listener" "client" {
  load_balancer_arn = aws_lb.client.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-FS-1-2-Res-2020-10"
  certificate_arn   = var.ssl_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.client.arn
  }
}

# Target Group
resource "aws_lb_target_group" "client" {
  name        = "paymentform-client-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
  }
}

# Security groups
resource "aws_security_group" "alb" {
  name_prefix = "client-alb-sg"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "client" {
  name_prefix = "client-service-sg"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# CloudWatch log group
resource "aws_cloudwatch_log_group" "client" {
  name              = "/ecs/paymentform-client"
  retention_in_days = var.log_retention_days
}

# IAM roles and policies
resource "aws_iam_role" "ecs_execution_role" {
  name = "paymentform-client-ecs-execution-role"

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
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "client_task_role" {
  name = "paymentform-client-task-role"

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
}