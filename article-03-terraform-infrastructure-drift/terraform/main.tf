data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "drift_demo" {
  name        = "${var.project_name}-sg"
  description = "Security group for Terraform infrastructure drift demonstration."
  tags = {
    Name        = "${var.project_name}-sg"
    Environment = "development"
    ManagedBy   = "Terraform"
  }
}

resource "aws_instance" "drift_demo" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.drift_demo.id]
  tags = {
    Name        = var.project_name
    Environment = "development"
    ManagedBy   = "Terraform"
  }
}