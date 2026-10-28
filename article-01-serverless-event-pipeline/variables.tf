variable "aws_region" {
  description = "AWS Region in which to create the example resources."
  type        = string
  default     = "ap-south-2"
}

variable "project_name" {
  description = "Prefix used for resource names. Keep it short and globally unique where required."
  type        = string
  default     = "s3-event-pipeline"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,28}$", var.project_name))
    error_message = "project_name must contain 3-28 lowercase letters, numbers, or hyphens."
  }
}

variable "lambda_timeout_seconds" {
  description = "Timeout for the Lambda function."
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout_seconds >= 1 && var.lambda_timeout_seconds <= 900
    error_message = "lambda_timeout_seconds must be between 1 and 900."
  }
}

variable "queue_visibility_timeout_seconds" {
  description = "SQS visibility timeout; keep greater than the Lambda timeout and allow for retries."
  type        = number
  default     = 180
}

variable "max_receive_count" {
  description = "Receive count after which SQS moves a message to the dead-letter queue."
  type        = number
  default     = 3
}
