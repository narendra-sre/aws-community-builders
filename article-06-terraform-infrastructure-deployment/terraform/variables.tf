variable "aws_region" {
  description = "AWS region for the demonstration bucket."
  type        = string
  default     = "ap-south-2"
}

variable "project_name" {
  description = "Short project identifier used in tags."
  type        = string
  default     = "acb-terraform-demo"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Use lowercase letters, numbers, and hyphens only."
  }
}

variable "environment" {
  description = "Environment tag."
  type        = string
  default     = "dev"
}

variable "bucket_name_prefix" {
  description = "Lowercase prefix for the globally unique S3 bucket name."
  type        = string
  default     = "acb-terraform-demo"

  validation {
    condition     = length(var.bucket_name_prefix) >= 3 && length(var.bucket_name_prefix) <= 40 && can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Prefix must be 3-40 characters, lowercase letters, numbers, or hyphens, and start/end with a letter or number."
  }
}
