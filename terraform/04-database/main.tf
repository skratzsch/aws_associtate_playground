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

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_prefix}-${var.environment}-db-subnet-group"
  subnet_ids = data.terraform_remote_state.networking.outputs.private_subnet_ids

  tags = {
    Name        = "${var.project_prefix}-${var.environment}-db-subnet-group"
    Environment = var.environment
    Project     = var.project_prefix
  }
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name        = "${var.project_prefix}-${var.environment}-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = data.terraform_remote_state.networking.outputs.vpc_id

  ingress {
    description     = "PostgreSQL from App Servers"
    from_port       = 5432
    to_port         = 5432
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
    Name        = "${var.project_prefix}-${var.environment}-rds-sg"
    Environment = var.environment
    Project     = var.project_prefix
  }
}

# RDS PostgreSQL Instance
resource "aws_db_instance" "main" {
  identifier     = "${var.project_prefix}-${var.environment}-postgres"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  backup_retention_period = var.backup_retention_period
  backup_window          = "03:00-04:00"
  maintenance_window     = "mon:04:00-mon:05:00"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  deletion_protection = false
  skip_final_snapshot = true

  tags = {
    Name        = "${var.project_prefix}-${var.environment}-postgres"
    Environment = var.environment
    Project     = var.project_prefix
  }
}

# Store DB credentials in SSM Parameter Store
resource "aws_ssm_parameter" "db_host" {
  name  = "/${var.project_prefix}/${var.environment}/db/host"
  type  = "String"
  value = aws_db_instance.main.address

  tags = {
    Environment = var.environment
    Project     = var.project_prefix
  }
}

resource "aws_ssm_parameter" "db_name" {
  name  = "/${var.project_prefix}/${var.environment}/db/name"
  type  = "String"
  value = var.db_name

  tags = {
    Environment = var.environment
    Project     = var.project_prefix
  }
}

resource "aws_ssm_parameter" "db_username" {
  name  = "/${var.project_prefix}/${var.environment}/db/username"
  type  = "String"
  value = var.db_username

  tags = {
    Environment = var.environment
    Project     = var.project_prefix
  }
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.project_prefix}/${var.environment}/db/password"
  type  = "SecureString"
  value = var.db_password

  tags = {
    Environment = var.environment
    Project     = var.project_prefix
  }
}