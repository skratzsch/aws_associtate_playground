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

# Data Sources - Networking Outputs
data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = "aws-associate-playground-terraform-state"
    key    = "dev/networking/terraform.tfstate"
    region = "eu-central-1"
  }
}

# Data Sources - Compute Outputs
data "terraform_remote_state" "compute" {
  backend = "s3"
  config = {
    bucket = "aws-associate-playground-terraform-state"
    key    = "dev/compute/terraform.tfstate"
    region = "eu-central-1"
  }
}

# Security Group für EFS
resource "aws_security_group" "efs" {
  name        = "${var.project_prefix}-efs-sg"
  description = "Security group for EFS mount targets"
  vpc_id      = data.terraform_remote_state.networking.outputs.vpc_id

  ingress {
    description     = "NFS from App Servers"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [data.terraform_remote_state.compute.outputs.app_server_security_group_id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_prefix}-efs-sg"
    Environment = var.environment
    Project     = var.project_prefix
  }
}

# EFS File System
resource "aws_efs_file_system" "main" {
  creation_token = "${var.project_prefix}-efs-${var.environment}"
  encrypted      = true

  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_${var.lifecycle_transition_to_ia_days}_DAYS"
  }

  tags = {
    Name        = "${var.project_prefix}-efs-${var.environment}"
    Environment = var.environment
    Project     = var.project_prefix
  }
}

# EFS Mount Targets (one per AZ in private subnets)
resource "aws_efs_mount_target" "main" {
  count           = length(data.terraform_remote_state.networking.outputs.private_subnet_ids)
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = data.terraform_remote_state.networking.outputs.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

# AWS Backup Vault
resource "aws_backup_vault" "efs_vault" {
  name = "${var.project_prefix}-efs-backup-vault-${var.environment}"

  tags = {
    Name        = "${var.project_prefix}-efs-backup-vault"
    Environment = var.environment
    Project     = var.project_prefix
  }
}


# AWS Backup Plan
resource "aws_backup_plan" "efs_backup" {
  name = "${var.project_prefix}-efs-backup-plan-${var.environment}"

  rule {
    rule_name         = "${var.project_prefix}-efs-daily-backup"
    target_vault_name = aws_backup_vault.efs_vault.name
    schedule          = var.backup_schedule

    lifecycle {
      delete_after = var.backup_retention_days
    }

    recovery_point_tags = {
      Environment = var.environment
      Project     = var.project_prefix
      Type        = "automatic"
    }
  }

  tags = {
    Name        = "${var.project_prefix}-efs-backup-plan"
    Environment = var.environment
    Project     = var.project_prefix
  }
}

# Backup Selection (EFS Resource)
resource "aws_backup_selection" "efs_backup_selection" {
  name         = "${var.project_prefix}-efs-backup-selection"
  plan_id      = aws_backup_plan.efs_backup.id
  iam_role_arn = var.backup_service_role_arn

  resources = [
    aws_efs_file_system.main.arn
  ]
}
