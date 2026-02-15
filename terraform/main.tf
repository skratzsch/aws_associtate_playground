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
  region = "eu-central-1"
}

# Dummy Resource zum Testen
resource "aws_s3_bucket" "test" {
  bucket = "test-bucket-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name        = "Test Bucket"
    Environment = "learning"
    ManagedBy   = "terraform"
  }
}

data "aws_caller_identity" "current" {}
