provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project   = "ACB-Article-09"
      ManagedBy = "Terraform"
      Purpose   = "SystemsManagerLearningLab"
    }
  }
}
