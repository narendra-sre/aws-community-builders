output "findings_table_name" {
  description = "DynamoDB table holding one audit record per processed event."
  value       = aws_dynamodb_table.findings.name
}

output "alerts_topic_arn" {
  description = "SNS topic receiving guardrail alerts."
  value       = aws_sns_topic.alerts.arn
}

output "remediator_function_name" {
  description = "Lambda function that evaluates and remediates violations."
  value       = aws_lambda_function.remediator.function_name
}

output "violations_rule_name" {
  description = "EventBridge rule matching violation API calls."
  value       = aws_cloudwatch_event_rule.violations.name
}

output "dlq_url" {
  description = "Dead-letter queue for events that failed all retries."
  value       = aws_sqs_queue.dlq.url
}
