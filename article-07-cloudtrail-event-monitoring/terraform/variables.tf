variable "aws_region" {
  description = "AWS region for this demonstration."
  type        = string
  default     = "ap-south-2"
}
variable "project_name" {
  description = "Project tag."
  type        = string
  default     = "cloudtrail-sg-change-alert"
}
variable "environment" {
  description = "Environment tag."
  type        = string
  default     = "demo"
}
variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "sg-change-alert"
}
