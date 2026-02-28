terraform {
  backend "s3" {
    bucket         = "aws-associate-playground-terraform-state"
    key            = "dev/compute-pet/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
