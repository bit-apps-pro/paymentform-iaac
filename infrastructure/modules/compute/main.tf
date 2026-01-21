terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# EC2 Launch Template
resource "aws_launch_template" "compute" {
  name_prefix   = "${var.environment}-compute-template"
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
  }))

  key_name               = var.key_pair_name
  monitoring             = var.detailed_monitoring
  ebs_optimized          = var.ebs_optimized

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.standard_tags,
      {
        Name = "${var.environment}-compute-instance"
      }
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      var.standard_tags,
      {
        Name = "${var.environment}-compute-volume"
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
  name_prefix = "${var.environment}-compute-asg-"

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
    value               = "${var.environment}-compute-instance"
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
  name = "${var.environment}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}

# IAM Role for ECS Instances
resource "aws_iam_role" "ecs_instance_role" {
  name = "${var.environment}-ecs-instance-role"

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
      Name = "${var.environment}-ecs-instance-role"
    }
  )
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

# CloudWatch Alarm for CPU utilization
resource "aws_cloudwatch_metric_alarm" "cpu_utilization_high" {
  alarm_name          = "${var.environment}-compute-cpu-high"
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
  alarm_name          = "${var.environment}-compute-cpu-low"
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
  name                   = "${var.environment}-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.compute.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${var.environment}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.compute.name
}