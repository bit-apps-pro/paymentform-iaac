# Cloudflare IP ranges (updated as of 2024)
# These should be kept up-to-date from: https://www.cloudflare.com/ips/

locals {
  cloudflare_ipv4_ranges = [
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
    "162.158.0.0/15",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "172.64.0.0/13",
    "131.0.72.0/22"
  ]

  cloudflare_ipv6_ranges = [
    "2400:cb00::/32",
    "2606:4700::/32",
    "2803:f800::/32",
    "2405:b500::/32",
    "2405:8100::/32",
    "2a06:98c0::/29",
    "2c0f:f248::/32"
  ]
}

# EC2 Security Group for instances behind Cloudflare
resource "aws_security_group" "ec2_cloudflare" {
  count = var.use_cloudflare ? 1 : 0

  name_prefix = "${var.environment}-ec2-cloudflare-sg"
  description = "Security group for EC2 instances behind Cloudflare"
  vpc_id      = var.vpc_id

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.environment}-ec2-cloudflare-security-group"
    }
  )
}

# Inbound HTTP from Cloudflare IPs only
resource "aws_security_group_rule" "ec2_cf_http" {
  count = var.use_cloudflare ? length(local.cloudflare_ipv4_ranges) : 0

  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [local.cloudflare_ipv4_ranges[count.index]]
  security_group_id = aws_security_group.ec2_cloudflare[0].id
  description       = "Allow HTTP from Cloudflare IP range ${count.index + 1}"
}

# Inbound HTTPS from Cloudflare IPs only
resource "aws_security_group_rule" "ec2_cf_https" {
  count = var.use_cloudflare ? length(local.cloudflare_ipv4_ranges) : 0

  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [local.cloudflare_ipv4_ranges[count.index]]
  security_group_id = aws_security_group.ec2_cloudflare[0].id
  description       = "Allow HTTPS from Cloudflare IP range ${count.index + 1}"
}

# SSH access (restricted)
resource "aws_security_group_rule" "ec2_ssh" {
  count = var.use_cloudflare && var.enable_ssh_access ? 1 : 0

  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.ssh_allowed_cidrs
  security_group_id = aws_security_group.ec2_cloudflare[0].id
  description       = "Allow SSH from trusted IPs"
}

# Allow all outbound traffic
resource "aws_security_group_rule" "ec2_egress_all" {
  count = var.use_cloudflare ? 1 : 0

  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ec2_cloudflare[0].id
  description       = "Allow all outbound traffic"
}

# Allow EC2 instances to communicate with each other (for Docker networking)
resource "aws_security_group_rule" "ec2_self" {
  count = var.use_cloudflare ? 1 : 0

  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  self              = true
  security_group_id = aws_security_group.ec2_cloudflare[0].id
  description       = "Allow EC2 instances to communicate with each other"
}
