terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  # Use instance_prefix when set (multi-instance deployments), else fall back to environment
  prefix = var.instance_prefix != "" ? var.instance_prefix : var.environment
}

# EC2 Launch Template
resource "aws_launch_template" "compute" {
  name_prefix   = "${local.prefix}-compute-template"
  image_id      = var.ami_id
  instance_type = var.instance_type

  vpc_security_group_ids = [
    var.ecs_security_group_id
  ]

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    ecs_cluster_name = var.ecs_cluster_name
    environment      = var.environment
    region           = var.region
    bucket_name      = var.bucket_name
    service_type     = var.service_type
  }))

  key_name      = var.key_pair_name
  ebs_optimized = var.ebs_optimized

  monitoring {
    enabled = var.detailed_monitoring
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.standard_tags,
      {
        Name = "${local.prefix}-compute-instance"
      }
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      var.standard_tags,
      {
        Name = "${local.prefix}-compute-volume"
      }
    )
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = var.root_volume_type
      delete_on_termination = true
      encrypted             = true
    }
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "compute" {
  name_prefix = "${local.prefix}-compute-asg-"

  vpc_zone_identifier = var.subnet_ids

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  launch_template {
    id      = aws_launch_template.compute.id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "${local.prefix}-compute-instance"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.standard_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

# IAM Instance Profile for ECS
resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "${local.prefix}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}

# IAM Role for ECS Instances
resource "aws_iam_role" "ecs_instance_role" {
  name = "${local.prefix}-ecs-instance-role"

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

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.prefix}-ecs-instance-role"
    }
  )

  lifecycle {
    prevent_destroy = true
  }
}

# Attach AWS managed policy for ECS instance role
resource "aws_iam_role_policy_attachment" "ecs_instance_role_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Attach SSM policy for instance management
resource "aws_iam_role_policy_attachment" "ssm_instance_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Minimal custom IAM policy to allow reading SSM parameters for the backend
resource "aws_iam_policy" "ssm_get_parameters" {
  name        = "${local.prefix}-ssm-get-parameters"
  description = "Allow reading specific SSM parameters for backend services"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:ssm:${var.region}:*:parameter/app/${var.environment}/backend/*"
      }
    ]
  })
}

# Attach the custom SSM read policy to the ECS instance role
resource "aws_iam_role_policy_attachment" "ssm_get_parameters_attachment" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = aws_iam_policy.ssm_get_parameters.arn
}

# CloudWatch Alarm for CPU utilization
resource "aws_cloudwatch_metric_alarm" "cpu_utilization_high" {
  alarm_name          = "${local.prefix}-compute-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = var.scaling_cpu_threshold
  alarm_description   = "This metric monitors EC2 instance CPU utilization"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.compute.name
  }

  alarm_actions = [
    aws_autoscaling_policy.scale_up.arn
  ]
}

resource "aws_cloudwatch_metric_alarm" "cpu_utilization_low" {
  alarm_name          = "${local.prefix}-compute-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = var.scaling_down_cpu_threshold
  alarm_description   = "This metric monitors EC2 instance CPU utilization for scaling down"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.compute.name
  }

  alarm_actions = [
    aws_autoscaling_policy.scale_down.arn
  ]
}

# Scaling policies
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${local.prefix}-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.compute.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${local.prefix}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.compute.name
}
# Data source to get instance IPs from ASG
data "aws_instances" "compute" {
  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [aws_autoscaling_group.compute.name]
  }

  depends_on = [aws_autoscaling_group.compute]
}
