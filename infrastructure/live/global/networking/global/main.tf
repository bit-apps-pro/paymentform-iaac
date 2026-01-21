terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "paymentform-global-state"
    key            = "networking/global/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "paymentform-terraform-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1" # Global resources typically managed from us-east-1

  default_tags {
    tags = {
      Project     = "paymentform"
      Environment = var.environment
      Component   = "networking-global"
      ManagedBy   = "terraform"
    }
  }
}

# Route53 hosted zone for the application domain
resource "aws_route53_zone" "primary" {
  name = var.domain_name

  tags = {
    Name        = "paymentform-domain"
    Environment = var.environment
  }
}

# ACM certificates for each region
resource "aws_acm_certificate" "backend" {
  domain_name       = "*.${var.domain_name}"
  validation_method = "DNS"

  subject_alternative_names = [
    "api.${var.domain_name}",
    "admin.${var.domain_name}",
    var.domain_name
  ]

  tags = {
    Name        = "paymentform-backend-cert"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate" "client" {
  domain_name       = "*.${var.domain_name}"
  validation_method = "DNS"

  subject_alternative_names = [
    "app.${var.domain_name}",
    var.domain_name
  ]

  tags = {
    Name        = "paymentform-client-cert"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate" "renderer" {
  domain_name       = "*.${var.domain_name}"
  validation_method = "DNS"

  subject_alternative_names = [
    "renderer.${var.domain_name}",
    "*-renderer.${var.domain_name}",
    var.domain_name
  ]

  tags = {
    Name        = "paymentform-renderer-cert"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront distributions for global CDN
resource "aws_cloudfront_distribution" "backend" {
  origin {
    domain_name = var.backend_load_balancer_dns
    origin_id   = "backend_lb"

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "https-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = 30
      origin_keepalive_timeout = 5
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for backend services"
  default_root_object = ""

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "backend_lb"

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
      headers = [
        "Access-Control-Request-Headers",
        "Access-Control-Request-Method",
        "Origin",
        "Authorization",
        "X-Tenant-ID"
      ]
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 300
    max_ttl                = 86400
    compress               = true
  }

  price_class = "PriceClass_All"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name        = "paymentform-backend-cf"
    Environment = var.environment
  }

  depends_on = [aws_acm_certificate.backend]
}

resource "aws_cloudfront_distribution" "client" {
  origin {
    domain_name = var.client_load_balancer_dns
    origin_id   = "client_lb"

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "https-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = 30
      origin_keepalive_timeout = 5
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for client dashboard"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "client_lb"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
  }

  price_class = "PriceClass_All"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name        = "paymentform-client-cf"
    Environment = var.environment
  }

  depends_on = [aws_acm_certificate.client]
}

resource "aws_cloudfront_distribution" "renderer" {
  origin {
    domain_name = var.renderer_load_balancer_dns
    origin_id   = "renderer_lb"

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "https-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = 30
      origin_keepalive_timeout = 5
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for renderer services"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "renderer_lb"

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 300
    max_ttl                = 86400
    compress               = true
  }

  price_class = "PriceClass_All"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name        = "paymentform-renderer-cf"
    Environment = var.environment
  }

  depends_on = [aws_acm_certificate.renderer]
}

# Regional load balancers for each service
resource "aws_lb" "backend_regional" {
  for_each = var.regional_endpoints

  name               = "paymentform-backend-${each.key}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[each.key].id]
  subnets            = each.value.subnets

  tags = {
    Name        = "paymentform-backend-${each.key}"
    Environment = var.environment
    Region      = each.key
  }
}

resource "aws_lb" "client_regional" {
  for_each = var.regional_endpoints

  name               = "paymentform-client-${each.key}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[each.key].id]
  subnets            = each.value.subnets

  tags = {
    Name        = "paymentform-client-${each.key}"
    Environment = var.environment
    Region      = each.key
  }
}

resource "aws_lb" "renderer_regional" {
  for_each = var.regional_endpoints

  name               = "paymentform-renderer-${each.key}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[each.key].id]
  subnets            = each.value.subnets

  tags = {
    Name        = "paymentform-renderer-${each.key}"
    Environment = var.environment
    Region      = each.key
  }
}

# Security groups for regional load balancers
resource "aws_security_group" "alb" {
  for_each = var.regional_endpoints

  name_prefix = "alb-${each.key}-sg"
  description = "Security group for ALB in ${each.key}"
  vpc_id      = each.value.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "alb-${each.key}-sg"
    Environment = var.environment
  }
}

# Regional target groups
resource "aws_lb_target_group" "backend_regional" {
  for_each = var.regional_endpoints

  name        = "paymentform-backend-${each.key}"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = each.value.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }

  tags = {
    Name        = "paymentform-backend-${each.key}-tg"
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "client_regional" {
  for_each = var.regional_endpoints

  name        = "paymentform-client-${each.key}"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = each.value.vpc_id
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

  tags = {
    Name        = "paymentform-client-${each.key}-tg"
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "renderer_regional" {
  for_each = var.regional_endpoints

  name        = "paymentform-renderer-${each.key}"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = each.value.vpc_id
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

  tags = {
    Name        = "paymentform-renderer-${each.key}-tg"
    Environment = var.environment
  }
}

# Regional listeners
resource "aws_lb_listener" "backend_https" {
  for_each = var.regional_endpoints

  load_balancer_arn = aws_lb.backend_regional[each.key].arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-FS-1-2-Res-2020-10"
  certificate_arn   = each.value.ssl_cert_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend_regional[each.key].arn
  }
}

resource "aws_lb_listener" "client_https" {
  for_each = var.regional_endpoints

  load_balancer_arn = aws_lb.client_regional[each.key].arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-FS-1-2-Res-2020-10"
  certificate_arn   = each.value.ssl_cert_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.client_regional[each.key].arn
  }
}

resource "aws_lb_listener" "renderer_https" {
  for_each = var.regional_endpoints

  load_balancer_arn = aws_lb.renderer_regional[each.key].arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-FS-1-2-Res-2020-10"
  certificate_arn   = each.value.ssl_cert_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.renderer_regional[each.key].arn
  }
}

# Route53 records for regional load balancing with latency-based routing
resource "aws_route53_record" "api" {
  for_each = var.regional_endpoints

  zone_id = aws_route53_zone.primary.zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

  latency_routing_policy {
    region = each.key
  }

  alias {
    name                   = aws_lb.backend_regional[each.key].dns_name
    zone_id                = aws_lb.backend_regional[each.key].zone_id
    evaluate_target_health = true
  }

  set_identifier = each.key
}

resource "aws_route53_record" "api_failover" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

  failover_routing_policy {
    type = "PRIMARY"
  }

  alias {
    name                   = aws_lb.backend_regional[keys(var.regional_endpoints)[0]].dns_name
    zone_id                = aws_lb.backend_regional[keys(var.regional_endpoints)[0]].zone_id
    evaluate_target_health = true
  }

  set_identifier = "failover-primary"
  weight         = 1
}

resource "aws_route53_record" "app" {
  for_each = var.regional_endpoints

  zone_id = aws_route53_zone.primary.zone_id
  name    = "app.${var.domain_name}"
  type    = "A"

  latency_routing_policy {
    region = each.key
  }

  alias {
    name                   = aws_lb.client_regional[each.key].dns_name
    zone_id                = aws_lb.client_regional[each.key].zone_id
    evaluate_target_health = true
  }

  set_identifier = each.key
}

resource "aws_route53_record" "renderer" {
  for_each = var.regional_endpoints

  zone_id = aws_route53_zone.primary.zone_id
  name    = "renderer.${var.domain_name}"
  type    = "A"

  latency_routing_policy {
    region = each.key
  }

  alias {
    name                   = aws_lb.renderer_regional[each.key].dns_name
    zone_id                = aws_lb.renderer_regional[each.key].zone_id
    evaluate_target_health = true
  }

  set_identifier = each.key
}

# WAF ACL for global protection
resource "aws_wafv2_web_acl" "global" {
  name  = "paymentform-global-waf"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSCRS"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSKBIRS"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "paymentform-global-waf"
    sampled_requests_enabled   = false
  }

  tags = {
    Name        = "paymentform-global-waf"
    Environment = var.environment
  }
}

# Attach WAF to CloudFront distributions
resource "aws_wafv2_web_acl_association" "backend_cf" {
  resource_arn = aws_cloudfront_distribution.backend.arn
  web_acl_arn  = aws_wafv2_web_acl.global.arn
}

resource "aws_wafv2_web_acl_association" "client_cf" {
  resource_arn = aws_cloudfront_distribution.client.arn
  web_acl_arn  = aws_wafv2_web_acl.global.arn
}

resource "aws_wafv2_web_acl_association" "renderer_cf" {
  resource_arn = aws_cloudfront_distribution.renderer.arn
  web_acl_arn  = aws_wafv2_web_acl.global.arn
}