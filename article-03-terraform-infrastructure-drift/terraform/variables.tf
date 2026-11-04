variable "aws_region" {
  description = "AWS region for the infrastructure drift detection"
  type        = string
  default     = "ap-south-2"
}

variable "instance_type" {
  description = "EC2 instance type for demonstration"
  type        = string
  default     = "t3.micro"
}

variable "project_name" {
  description = "Name of the Article 3 project."
  type        = string
  default     = "Terraform infrastructure drift"
}