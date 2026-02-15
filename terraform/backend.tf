terraform {
  backend "s3" {
    bucket         = "aws-associate-playground-terraform-state"
    key            = "terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
