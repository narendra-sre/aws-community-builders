resource "random_id" "bucket_suffix" {
  byte_length = 4
}

module "secure_s3_bucket" {
  source = "../modules/secure_s3_bucket"

  bucket_name = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "${var.project_name}-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}
