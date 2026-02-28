terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

data "terraform_remote_state" "security" {
  backend = "s3"
  config = {
    bucket = "aws-associate-playground-terraform-state"
    key    = "dev/security/terraform.tfstate"
    region = "eu-central-1"
  }
}

data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = "aws-associate-playground-terraform-state"
    key    = "dev/networking/terraform.tfstate"
    region = "eu-central-1"
  }
}

# S3 Bucket für Ansible SSM Connection Plugin (temporäre Dateien)
resource "aws_s3_bucket" "ansible_tmp" {
  bucket        = "${var.project_prefix}-ansible-tmp-${var.environment}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name        = "${var.project_prefix}-ansible-tmp"
    Environment = var.environment
    Project     = var.project_prefix
  }
}

resource "aws_s3_bucket_public_access_block" "ansible_tmp" {
  bucket                  = aws_s3_bucket.ansible_tmp.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ansible_tmp" {
  bucket = aws_s3_bucket.ansible_tmp.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "ansible_tmp" {
  bucket = aws_s3_bucket.ansible_tmp.id
  rule {
    id     = "delete-old-tmp-files"
    status = "Enabled"
    expiration {
      days = 1
    }
  }
}

resource "aws_s3_bucket_policy" "ansible_tmp" {
  bucket = aws_s3_bucket.ansible_tmp.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = data.terraform_remote_state.security.outputs.ec2_instance_role_arn }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.ansible_tmp.arn,
          "${aws_s3_bucket.ansible_tmp.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_security_group" "pet" {
  name        = "${var.project_prefix}-pet-sg"
  description = "Security group for Pet EC2 instance"
  vpc_id      = data.terraform_remote_state.networking.outputs.vpc_id

  ingress {
    description      = "HTTP from Internet"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description = "Allow all outbound IPv4"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description      = "Allow all outbound IPv6"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name        = "${var.project_prefix}-pet-sg"
    Environment = var.environment
    Project     = var.project_prefix
  }
}

resource "aws_instance" "pet" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = data.terraform_remote_state.networking.outputs.public_subnet_ids[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.pet.id]
  iam_instance_profile        = data.terraform_remote_state.security.outputs.ec2_instance_profile_name

  user_data = base64encode(<<-EOF
    #!/bin/bash
    systemctl start amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    EOF
  )

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring = true

  tags = {
    Name            = "${var.project_prefix}-pet"
    Environment     = var.environment
    Project         = var.project_prefix
    deployment_type = "pet"
  }
}
