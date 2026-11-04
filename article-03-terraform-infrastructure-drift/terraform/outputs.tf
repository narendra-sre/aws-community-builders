output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.drift_demo.id
}

output "instance_type" {
  description = "EC2 instance type"
  value       = aws_instance.drift_demo.instance_type
}

output "instance_ami" {
  description = "EC2 instance ami"
  value       = aws_instance.drift_demo.ami
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.drift_demo.id
}

output "aws_region" {
  description = "AWS deployment region"
  value       = var.aws_region
}