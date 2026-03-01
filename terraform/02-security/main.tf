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

# KMS Key für Secrets Encryption
resource "aws_kms_key" "secrets" {
  description             = "KMS key for encrypting secrets"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name        = "${var.project_prefix}-secrets-kms"
    Environment = var.environment
    Project     = var.project_prefix
  }
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.project_prefix}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# Secrets Manager - GitHub Token (Placeholder)
resource "aws_secretsmanager_secret" "github_token" {
  name                    = "${var.project_prefix}-github-token"
  kms_key_id              = aws_kms_key.secrets.arn
  recovery_window_in_days = 0

  tags = {
    Name        = "${var.project_prefix}-github-token"
    Environment = var.environment
    Project     = var.project_prefix
  }
}

resource "aws_secretsmanager_secret_version" "github_token" {
  secret_id = aws_secretsmanager_secret.github_token.id
  secret_string = jsonencode({
    token = "PLACEHOLDER_SET_MANUALLY"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# IAM Role für EC2 Instances
resource "aws_iam_role" "ec2_instance" {
  name = "${var.project_prefix}-ec2-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_prefix}-ec2-instance-role"
    Environment = var.environment
    Project     = var.project_prefix
  }
}

# IAM Policy für SSM Session Manager
resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Policy für CloudWatch Logs
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Custom Policy für Secrets Manager + SSM Parameter Store Read
resource "aws_iam_policy" "secrets_read" {
  name        = "${var.project_prefix}-secrets-read"
  description = "Allow reading secrets from Secrets Manager and SSM Parameter Store"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.github_token.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = [
          aws_kms_key.secrets.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.region}:*:parameter/${var.project_prefix}/${var.environment}/db/*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_prefix}-secrets-read"
    Environment = var.environment
    Project     = var.project_prefix
  }
}

resource "aws_iam_role_policy_attachment" "secrets_read" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = aws_iam_policy.secrets_read.arn
}

# Data Source - GitHub Actions Role
data "aws_iam_role" "github_actions" {
  name = "github-actions-terraform"
}

# Policy: GitHub Actions darf AWSBackupDefaultServiceRole passieren
resource "aws_iam_role_policy" "github_actions_backup_passrole" {
  name = "backup-passrole"
  role = data.aws_iam_role.github_actions.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = var.backup_service_role_arn
      }
    ]
  })
}

# Policy: GitHub Actions darf Packer-AMIs bauen (EC2 + SSM Session Manager communicator)
resource "aws_iam_role_policy" "github_actions_packer" {
  name = "packer-ami-build"
  role = data.aws_iam_role.github_actions.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:StopInstances",
          "ec2:TerminateInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:CreateImage",
          "ec2:DeregisterImage",
          "ec2:DescribeImages",
          "ec2:DeleteSnapshot",
          "ec2:DescribeSnapshots",
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DescribeSecurityGroups",
          "ec2:CreateKeyPair",
          "ec2:DeleteKeyPair",
          "ec2:DescribeKeyPairs",
          "ec2:CreateTags",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs"
        ]
        Resource = "*"
      },
      {
        # SSM Session Manager communicator: runner tunnels into Packer build instance
        Effect = "Allow"
        Action = [
          "ssm:StartSession",
          "ssm:TerminateSession",
          "ssm:GetConnectionStatus"
        ]
        Resource = [
          "arn:aws:ec2:*:*:instance/*",
          "arn:aws:ssm:*::document/AWS-StartSSHSession"
        ]
      },
      {
        # PassRole + GetInstanceProfile: pass and validate the EC2 instance profile
        Effect = "Allow"
        Action = [
          "iam:PassRole",
          "iam:GetInstanceProfile"
        ]
        Resource = [
          aws_iam_role.ec2_instance.arn,
          aws_iam_instance_profile.ec2_instance.arn
        ]
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_instance" {
  name = "${var.project_prefix}-ec2-instance-profile"
  role = aws_iam_role.ec2_instance.name

  tags = {
    Name        = "${var.project_prefix}-ec2-instance-profile"
    Environment = var.environment
    Project     = var.project_prefix
  }
}

