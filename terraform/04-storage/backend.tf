terraform {
  backend "s3" {
    bucket = "aws-associate-playground-terraform-state"
    key    = "dev/storage/terraform.tfstate"
    region = "eu-central-1"
  }
}

