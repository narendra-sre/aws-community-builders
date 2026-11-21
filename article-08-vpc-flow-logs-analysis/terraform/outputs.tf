output "flow_logs_bucket_name" {
  description = "S3 bucket storing VPC Flow Logs"
  value       = aws_s3_bucket.logs.bucket
}

output "flow_log_id" {
  description = "Created VPC Flow Log ID"
  value       = aws_flow_log.vpc.id
}

output "athena_workgroup_name" {
  description = "Athena workgroup name"
  value       = aws_athena_workgroup.logs.name
}

output "selected_vpc_id" {
  description = "VPC monitored by Flow Logs"
  value       = var.vpc_id
}
