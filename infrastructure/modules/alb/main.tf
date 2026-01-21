terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.enable_deletion_protection

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.environment}-application-load-balancer"
    }
  )
}

# Target Group for Backend API (port 8000)
resource "aws_lb_target_group" "backend" {
  name        = "${var.environment}-backend-tg"
  port        = 8000
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = var.backend_health_check_path
    matcher             = "200"
  }

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.environment}-backend-target-group"
    }
  )
}

# Target Group for Frontend (port 3000)
resource "aws_lb_target_group" "frontend" {
  name        = "${var.environment}-frontend-tg"
  port        = 3000
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = var.frontend_health_check_path
    matcher             = "200"
  }

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.environment}-frontend-target-group"
    }
  )
}

# HTTP Listener (redirects to HTTPS)
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS Listener (requires ACM certificate ARN)
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.ssl_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  # Add host header conditions for routing to different target groups
  dynamic "default_action" {
    for_each = var.route_to_frontend ? [1] : []
    content {
      type = "fixed-response"
      fixed_response {
        content_type = "text/plain"
        message_body = "Default route configured to frontend"
        status_code  = "200"
      }
    }
  }
}

# Rule to forward requests to frontend based on path or host
resource "aws_lb_listener_rule" "frontend_rule" {
  count = var.enable_frontend_routing ? 1 : 0

  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }

  condition {
    path_pattern {
      values = var.frontend_path_patterns
    }
  }
}

# Rule to forward requests to backend based on path or host
resource "aws_lb_listener_rule" "backend_rule" {
  count = var.enable_backend_routing ? 1 : 0

  listener_arn = aws_lb_listener.https.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = var.backend_path_patterns
    }
  }
}

# CloudWatch log group for ALB access logs
resource "aws_cloudwatch_log_group" "alb_access_logs" {
  name              = "/aws/alb/${var.environment}-alb-access-logs"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.environment}-alb-access-logs"
    }
  )
}

# S3 bucket for storing ALB access logs (if enabled)
resource "aws_s3_bucket" "alb_logs" {
  count  = var.enable_access_logs ? 1 : 0
  bucket = "${var.environment}-alb-access-logs-${random_string.suffix.result}"

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.environment}-alb-logs-bucket"
    }
  )
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs_encryption" {
  count  = var.enable_access_logs ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "random_string" "suffix" {
  count   = var.enable_access_logs ? 1 : 0
  length  = 8
  special = false
  upper   = false
}