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

locals {
  # AWS limits: NLB name ≤32 chars, target group name ≤32 chars.
  # Use a short env+label combo for TG names to stay well within limits.
  # e.g. environment="prod-us", service_label="bknd" → tg_prefix="prod-us-bknd"
  tg_prefix      = "${var.environment}-${var.service_label}"
  webhook_enabled = var.alert_webhook_url != ""
}

# Security Group for NLB
resource "aws_security_group" "nlb" {
  name_prefix = "${var.prefix}-nlb-sg"
  vpc_id      = var.vpc_id

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.prefix}-nlb-sg"
    }
  )
}

resource "aws_security_group_rule" "nlb_ingress_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.nlb.id
  description       = "Allow HTTPS from anywhere"
}

resource "aws_security_group_rule" "nlb_ingress_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.nlb.id
  description       = "Allow HTTP from anywhere"
}

resource "aws_security_group_rule" "nlb_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.nlb.id
  description       = "Allow all outbound"
}

# NLB
resource "aws_lb" "main" {
  name               = "${var.prefix}-nlb"
  internal           = false
  load_balancer_type = "network"
  security_groups    = [aws_security_group.nlb.id]
  subnets            = var.subnet_ids

  enable_deletion_protection = var.enable_deletion_protection

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.prefix}-nlb"
    }
  )
}

# Target Group - HTTPS (port 443) - TCP passthrough, Caddy handles TLS inside container
resource "aws_lb_target_group" "https" {
  name                 = "${local.tg_prefix}-https-tg"
  port                 = 443
  protocol             = "TCP"
  vpc_id               = var.vpc_id
  deregistration_delay = 30
  preserve_client_ip   = true

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 10
    protocol            = "HTTP"
    port                = "80"
    path                = "/health"
    matcher             = "200"
  }

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.tg_prefix}-https-tg"
    }
  )
}

# NLB Listener - TCP 443 → HTTPS target group
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.https.arn
  }
}

# Target Group - HTTP (port 80) - TCP passthrough, Cloudflare terminates TLS at the edge
resource "aws_lb_target_group" "http" {
  name                 = "${local.tg_prefix}-http-tg"
  port                 = 80
  protocol             = "TCP"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  # Preserve client IP so the backend sees Cloudflare's edge IP as the source.
  # This allows Cloudflare headers (CF-Connecting-IP, CF-IPCountry) to flow
  # through to the application while the SG still restricts to Cloudflare CIDRs.
  preserve_client_ip = true

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 10
    protocol            = "HTTP"
    port                = "80"
    path                = "/health"
    matcher             = "200"
  }

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.tg_prefix}-http-tg"
    }
  )
}

# NLB Listener - TCP 80 → HTTP target group
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http.arn
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

  alarm_name          = "${var.prefix}-all-targets-unhealthy"
  alarm_description   = "All targets in ${var.prefix} HTTP target group have been unhealthy for ${var.alert_sustained_minutes} minute(s). Webhook will fire."
  namespace           = "AWS/NetworkELB"
  metric_name         = "HealthyHostCount"
  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.http.arn_suffix
  }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = var.alert_sustained_minutes
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.alert[0].arn]
  ok_actions    = [aws_sns_topic.alert[0].arn]

  tags = merge(var.standard_tags, { Name = "${var.prefix}-all-targets-unhealthy" })
}

# SNS topic — Lambda subscribes to this
resource "aws_sns_topic" "alert" {
  count = local.webhook_enabled ? 1 : 0
  name  = "${var.prefix}-health-alert"
  tags  = merge(var.standard_tags, { Name = "${var.prefix}-health-alert" })
}

# IAM role for the Lambda
resource "aws_iam_role" "webhook_lambda" {
  count = local.webhook_enabled ? 1 : 0
  name  = "${var.prefix}-webhook-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.standard_tags, { Name = "${var.prefix}-webhook-lambda" })
}

resource "aws_iam_role_policy_attachment" "webhook_lambda_logs" {
  count      = local.webhook_enabled ? 1 : 0
  role       = aws_iam_role.webhook_lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda function — inline Node.js that POSTs to the webhook URL
resource "aws_lambda_function" "webhook" {
  count         = local.webhook_enabled ? 1 : 0
  function_name = "${var.prefix}-health-webhook"
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

  tags = merge(var.standard_tags, { Name = "${var.prefix}-health-webhook" })
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
