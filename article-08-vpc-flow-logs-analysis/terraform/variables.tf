variable "aws_region" {
  type    = string
  default = "ap-south-2"
}
variable "vpc_id" {
  description = "Existing VPC ID to monitor."
  type        = string
}
variable "project_name" {
  type    = string
  default = "article08-flowlogs"
}
