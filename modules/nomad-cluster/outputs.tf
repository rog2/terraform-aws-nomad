output "asg_name" {
  value = aws_autoscaling_group.autoscaling_group.name
}

output "cluster_tag_key" {
  value = var.cluster_tag_key
}

output "cluster_tag_value" {
  value = var.cluster_tag_value
}

output "cluster_size" {
  value = aws_autoscaling_group.autoscaling_group.desired_capacity
}

output "launch_template_name" {
  value = aws_launch_template.launch_template.name
}

output "launch_template_id" {
  value = aws_launch_template.launch_template.id
}

output "iam_role_arn" {
  value = aws_iam_role.instance_role.arn
}

output "iam_role_id" {
  value = aws_iam_role.instance_role.id
}

output "security_group_id" {
  value = aws_security_group.lc_security_group.id
}
