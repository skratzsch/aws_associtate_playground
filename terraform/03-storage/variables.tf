variable "region" {
  description = "AWS Region"
  type        = string
  default     = "eu-central-1"
}

variable "project_prefix" {
  description = "Project prefix for resource naming"
  type        = string
  default     = "capstone"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "lifecycle_transition_to_ia_days" {
  description = "Number of days after which files are transitioned to Infrequent Access"
  type        = number
  default     = 30
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

variable "backup_schedule" {
  description = "Cron expression for backup schedule"
  type        = string
  default     = "cron(0 2 * * ? *)" # Daily at 2 AM UTC
}

