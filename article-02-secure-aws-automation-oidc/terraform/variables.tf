variable "aws_region" {
  description = "AWS Region used by the GitHub Actions workflow."
  type        = string
  default     = "ap-south-2"
}

variable "github_oidc_provider_arn" {
  description = "ARN of the existing GitHub Actions OIDC provider in this AWS account."
  type        = string
}

variable "github_oidc_subject" {
  description = "Exact sub claim observed in the GitHub OIDC token for the trusted workflow. Supports legacy and immutable subject formats."
  type        = string

  validation {
    condition     = length(trimspace(var.github_oidc_subject)) > 0
    error_message = "github_oidc_subject must be the exact, non-empty subject claim issued by the trusted GitHub workflow."
  }
}

variable "demo_bucket_name" {
  description = "Existing dedicated test bucket whose reports/ prefix the role may read."
  type        = string
}
