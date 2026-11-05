variable "aws_region" {
  description = "AWS region to deploy into (Asia Pacific Hyderabad by default)."
  type        = string
  default     = "ap-south-2"
}

variable "project_name" {
  description = "Prefix used for all resource names."
  type        = string
  default     = "sg-s3-guardrails"
}

variable "alert_email" {
  description = "Email address that receives guardrail alerts. Confirm the SNS subscription email after apply."
  type        = string
}

variable "dry_run" {
  description = "When true, the remediator only records and alerts on violations. Set to false to enforce."
  type        = bool
  default     = true
}

variable "sensitive_ports" {
  description = "Comma-separated TCP ports that must never be open to the internet."
  type        = string
  default     = "22,3389"
}

variable "exempt_tag_key" {
  description = "Tag key that exempts a security group or bucket when its value is 'true'."
  type        = string
  default     = "guardrail-exempt"
}
