variable "aws_region" {
  description = "AWS Region for the lab."
  type        = string
  default     = "ap-south-2"
}
variable "instance_type" {
  description = "Confirm regional availability and current pricing before deployment."
  type        = string
  default     = "t3.micro"
}
variable "name_prefix" {
  type    = string
  default = "acb-article-09"
}
