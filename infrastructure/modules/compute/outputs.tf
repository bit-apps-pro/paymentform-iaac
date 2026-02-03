output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.compute.id
}

output "launch_template_id" {
  description = "ID of the launch template"
  value       = aws_launch_template.compute.id
}

output "launch_template_name" {
  description = "Name of the launch template"
  value       = aws_launch_template.compute.name
}

output "instance_profile_arn" {
  description = "ARN of the IAM instance profile"
  value       = aws_iam_instance_profile.ecs_instance_profile.arn
}

output "instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = aws_iam_instance_profile.ecs_instance_profile.name
}

output "instance_role_arn" {
  description = "ARN of the IAM instance role"
  value       = aws_iam_role.ecs_instance_role.arn
}

output "instance_role_name" {
  description = "Name of the IAM instance role"
  value       = aws_iam_role.ecs_instance_role.name
}

output "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.compute.arn
}

output "autoscaling_group_min_size" {
  description = "Minimum size of the Auto Scaling Group"
  value       = aws_autoscaling_group.compute.min_size
}

output "autoscaling_group_max_size" {
  description = "Maximum size of the Auto Scaling Group"
  value       = aws_autoscaling_group.compute.max_size
}

output "autoscaling_group_desired_capacity" {
  description = "Desired capacity of the Auto Scaling Group"
  value       = aws_autoscaling_group.compute.desired_capacity
}

output "instance_ips" {
  description = "List of EC2 instance public/private IP addresses"
  value       = data.aws_instances.compute.public_ips != [] ? data.aws_instances.compute.public_ips : data.aws_instances.compute.private_ips
}
