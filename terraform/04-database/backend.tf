terraform {
  backend "s3" {
    bucket = "aws-associate-playground-terraform-state"
    key    = "dev/database/terraform.tfstate"
    region = "eu-central-1"
  }
}