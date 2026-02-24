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

variable "ami_id" {
  description = "AMI ID for EC2 instances (Ubuntu with nginx)"
  type        = string
  default     = "ami-0084a47cc718c111a" # Ubuntu 22.04 LTS in eu-central-1
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "instance_profile_name" {
  description = "IAM instance profile name"
  type        = string
  default     = ""
}

variable "asg_max_size" {
  description = "Maximum size of Auto Scaling Group"
  type        = number
  default     = 4
}

variable "health_check_path" {
  description = "Health check path for target group"
  type        = string
  default     = "/"
}
