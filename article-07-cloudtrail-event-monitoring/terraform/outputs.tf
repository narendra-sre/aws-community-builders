output "sns_topic_arn" {
  description = "SNS topic ARN."
  value       = aws_sns_topic.security_group_alerts.arn
}
output "eventbridge_rule_name" {
  description = "EventBridge rule name."
  value       = aws_cloudwatch_event_rule.security_group_changes.name
}
output "test_security_group_id" {
  description = "Dedicated test security group ID."
  value       = aws_security_group.test.id
}
output "aws_region" {
  description = "AWS region."
  value       = var.aws_region
}
