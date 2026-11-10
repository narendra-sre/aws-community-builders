output "bucket_name" {
  description = "Name of the created S3 bucket."
  value       = module.secure_s3_bucket.bucket_name
}

output "bucket_arn" {
  description = "ARN of the created S3 bucket."
  value       = module.secure_s3_bucket.bucket_arn
}

output "bucket_region" {
  description = "AWS region containing the bucket."
  value       = var.aws_region
}
