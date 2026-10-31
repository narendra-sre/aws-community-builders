variable "aws_region" {
  description = "AWS Region used by the GitHub Actions workflow."
  type        = string
  default     = "ap-south-2"
}
variable "github_oidc_provider_arn" {
  description = "ARN of the existing GitHub Actions OIDC provider in this AWS account."
  type        = string
}
variable "github_owner" {
  description = "GitHub repository owner or organization."
  type        = string
}
variable "github_repository" {
  description = "GitHub repository name, without owner."
  type        = string
}
variable "github_branch" {
  description = "Only this branch is trusted by the role."
  type        = string
  default     = "main"
}
variable "demo_bucket_name" {
  description = "Existing dedicated test bucket whose reports/ prefix the role may read."
  type        = string
}
