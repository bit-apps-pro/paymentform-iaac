terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

# Fetch Cloudflare IP ranges for ingress restriction
data "http" "cloudflare_ips_v4" {
  url = "https://www.cloudflare.com/ips-v4"
}

data "http" "cloudflare_ips_v6" {
  url = "https://www.cloudflare.com/ips-v6"
}

locals {
  cloudflare_ipv4_ranges = try(
    compact(split("\n", trimspace(data.http.cloudflare_ips_v4.response_body))),
    ["173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22", "141.101.64.0/18", "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20", "197.234.240.0/22", "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13", "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22"]
  )
  cloudflare_ipv6_ranges = try(
    compact(split("\n", trimspace(data.http.cloudflare_ips_v6.response_body))),
    ["2400:cb00::/32", "2606:4700::/32", "2803:f800::/32", "2405:b500::/32", "2405:8100::/32", "2a06:98c0::/29", "2c0f:f248::/32"]
  )
  webhook_enabled = var.alert_webhook_url != ""
}

# =============================================================================
# Application Load Balancer (ALB)
# =============================================================================

resource "aws_lb" "this" {
  name               = "${var.prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = var.subnet_ids
  security_groups    = [aws_security_group.alb.id]

  idle_timeout                     = var.idle_timeout
  enable_deletion_protection       = var.enable_deletion_protection
  enable_cross_zone_load_balancing = true
  drop_invalid_header_fields       = true

  tags = merge(var.standard_tags, {
    Name = "${var.prefix}-alb"
  })
}

# =============================================================================
# ALB Security Group — Cloudflare ingress only (80/443), all egress
# =============================================================================

resource "aws_security_group" "alb" {
  name_prefix = "${var.prefix}-alb-sg"
  description = "ALB security group - Cloudflare ingress only"
  vpc_id      = var.vpc_id

  tags = merge(var.standard_tags, {
    Name = "${var.prefix}-alb-sg"
  })
}

resource "aws_security_group_rule" "alb_ingress_443_cf_v4" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = local.cloudflare_ipv4_ranges
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from Cloudflare (IPv4)"
}

resource "aws_security_group_rule" "alb_ingress_443_cf_v6" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  ipv6_cidr_blocks  = local.cloudflare_ipv6_ranges
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from Cloudflare (IPv6)"
}

resource "aws_security_group_rule" "alb_ingress_80_cf_v4" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = local.cloudflare_ipv4_ranges
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from Cloudflare (IPv4, for redirect to HTTPS)"
}

resource "aws_security_group_rule" "alb_ingress_80_cf_v6" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  ipv6_cidr_blocks  = local.cloudflare_ipv6_ranges
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from Cloudflare (IPv6, for redirect to HTTPS)"
}

resource "aws_security_group_rule" "alb_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "All outbound"
}

# =============================================================================
# Target Group — HTTP on port 80 with sticky sessions for WebSocket persistence
# =============================================================================

resource "aws_lb_target_group" "this" {
  name                 = "${var.environment}-${var.service_label}-alb-tg"
  port                 = 80
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "instance"
  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = var.stickiness_cookie_duration
    enabled         = true
  }

  tags = merge(var.standard_tags, {
    Name = "${var.environment}-${var.service_label}-alb-tg"
  })
}

# =============================================================================
# ALB Listeners
# =============================================================================

# HTTPS listener — forward to target group
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

# HTTP listener — redirect 301 to HTTPS
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
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

# =============================================================================
# Persistent unhealthy alert: CloudWatch → SNS → Lambda → webhook
# All resources are conditional on alert_webhook_url being set.
# =============================================================================

# CloudWatch alarm: fires when HealthyHostCount == 0 for alert_sustained_minutes
# consecutive periods of 60 s each (i.e. all targets unhealthy for N minutes).
resource "aws_cloudwatch_metric_alarm" "unhealthy" {
  count = local.webhook_enabled ? 1 : 0

  alarm_name          = "${var.prefix}-alb-all-targets-unhealthy"
  alarm_description   = "All targets in ${var.prefix} ALB target group have been unhealthy for ${var.alert_sustained_minutes} minute(s). Webhook will fire."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
    TargetGroup  = aws_lb_target_group.this.arn_suffix
  }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = var.alert_sustained_minutes
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.alert[0].arn]
  ok_actions    = [aws_sns_topic.alert[0].arn]

  tags = merge(var.standard_tags, { Name = "${var.prefix}-alb-all-targets-unhealthy" })
}

# SNS topic — Lambda subscribes to this
resource "aws_sns_topic" "alert" {
  count = local.webhook_enabled ? 1 : 0
  name  = "${var.prefix}-alb-health-alert"
  tags  = merge(var.standard_tags, { Name = "${var.prefix}-alb-health-alert" })
}

# IAM role for the Lambda
resource "aws_iam_role" "webhook_lambda" {
  count = local.webhook_enabled ? 1 : 0
  name  = "${var.prefix}-alb-webhook-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.standard_tags, { Name = "${var.prefix}-alb-webhook-lambda" })
}

resource "aws_iam_role_policy_attachment" "webhook_lambda_logs" {
  count      = local.webhook_enabled ? 1 : 0
  role       = aws_iam_role.webhook_lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda function — inline Node.js that POSTs to the webhook URL
resource "aws_lambda_function" "webhook" {
  count         = local.webhook_enabled ? 1 : 0
  function_name = "${var.prefix}-alb-health-webhook"
  role          = aws_iam_role.webhook_lambda[0].arn
  runtime       = "nodejs22.x"
  handler       = "index.handler"
  timeout       = 10

  environment {
    variables = {
      WEBHOOK_URL  = var.alert_webhook_url
      SERVICE_NAME = var.prefix
    }
  }

  # Inline zip: small Node.js handler embedded via archive_file
  filename         = data.archive_file.webhook_lambda[0].output_path
  source_code_hash = data.archive_file.webhook_lambda[0].output_base64sha256

  tags = merge(var.standard_tags, { Name = "${var.prefix}-alb-health-webhook" })
}

data "archive_file" "webhook_lambda" {
  count       = local.webhook_enabled ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/webhook_lambda_${var.prefix}.zip"

  source {
    filename = "index.mjs"
    content  = <<-JS
      import https from "https";
      import http from "http";

      export async function handler(event) {
        const record  = event?.Records?.[0]?.Sns ?? {};
        const subject = record.Subject ?? "Health alert";
        const message = record.Message ?? JSON.stringify(event);

        let alarmState = "UNKNOWN";
        try { alarmState = JSON.parse(message).NewStateValue ?? alarmState; } catch {}

        const body = JSON.stringify({
          service:   process.env.SERVICE_NAME,
          state:     alarmState,
          subject,
          message,
          timestamp: new Date().toISOString(),
        });

        const url    = new URL(process.env.WEBHOOK_URL);
        const client = url.protocol === "https:" ? https : http;

        await new Promise((resolve, reject) => {
          const req = client.request(
            { hostname: url.hostname, port: url.port || (url.protocol === "https:" ? 443 : 80),
              path: url.pathname + url.search, method: "POST",
              headers: { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(body) } },
            (res) => { res.resume(); resolve(res.statusCode); }
          );
          req.on("error", reject);
          req.write(body);
          req.end();
        });
      }
    JS
  }
}

# Allow SNS to invoke the Lambda
resource "aws_lambda_permission" "sns_invoke" {
  count         = local.webhook_enabled ? 1 : 0
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.webhook[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alert[0].arn
}

# Subscribe Lambda to the SNS topic
resource "aws_sns_topic_subscription" "lambda" {
  count     = local.webhook_enabled ? 1 : 0
  topic_arn = aws_sns_topic.alert[0].arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.webhook[0].arn
}
