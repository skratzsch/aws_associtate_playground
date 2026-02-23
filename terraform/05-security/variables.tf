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

