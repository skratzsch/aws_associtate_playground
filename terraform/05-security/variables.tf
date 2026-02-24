variable "region" {
  description = "AWS Region"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_prefix" {
  description = "Project prefix for resource naming"
  type        = string
  default     = "tuwa"
}

variable "backup_service_role_arn" {
  description = "ARN of the AWS Backup service role that GitHub Actions needs to pass"
  type        = string
  default     = "arn:aws:iam::891376982602:role/service-role/AWSBackupDefaultServiceRole"
}

