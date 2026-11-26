output "aws_region" { value = var.aws_region }
output "instance_id" { value = aws_instance.managed.id }
output "instance_public_ip" {
  description = "Used for outbound connectivity in this lab, not for inbound SSH."
  value       = aws_instance.managed.public_ip
}
output "security_group_id" { value = aws_security_group.instance.id }
output "ssm_instance_role" { value = aws_iam_role.ssm_instance.name }
