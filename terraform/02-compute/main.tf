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

# Security Group für ALB
resource "aws_security_group" "alb" {
  name        = "${var.project_prefix}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = data.terraform_remote_state.networking.outputs.vpc_id

  ingress {
    description      = "HTTP from Internet"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "HTTPS from Internet"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description = "Allow all outbound IPv4"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description      = "Allow all outbound IPv6"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name        = "${var.project_prefix}-alb-sg"
    Environment = var.environment
    Project     = var.project_prefix
  }
}

# Security Group für App Server
resource "aws_security_group" "app_server" {
  name        = "${var.project_prefix}-app-server-sg"
  description = "Security group for Application Servers"
  vpc_id      = data.terraform_remote_state.networking.outputs.vpc_id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description      = "Allow all outbound IPv6"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name        = "${var.project_prefix}-app-server-sg"
    Environment = var.environment
    Project     = var.project_prefix
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.terraform_remote_state.networking.outputs.public_subnet_ids
  ip_address_type    = "dualstack"

  enable_deletion_protection       = false
  enable_http2                     = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name        = "${var.project_prefix}-alb"
    Environment = var.environment
    Project     = var.project_prefix
  }
}

# Target Group
resource "aws_lb_target_group" "app" {
  name            = "${var.project_prefix}-app-tg"
  port            = 80
  protocol        = "HTTP"
  vpc_id          = data.terraform_remote_state.networking.outputs.vpc_id
  ip_address_type = "ipv6"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = var.health_check_path
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = {
    Name        = "${var.project_prefix}-app-tg"
    Environment = var.environment
    Project     = var.project_prefix
  }
}

# ALB Listener HTTP
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = {
    Name        = "${var.project_prefix}-alb-listener-http"
    Environment = var.environment
    Project     = var.project_prefix
  }
}

# Launch Template
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_prefix}-app-"
  image_id      = var.ami_id # Verwende Ubuntu AMI (z.B. ami-0084a47cc718c111a für Ubuntu 22.04 in eu-central-1)
  instance_type = var.instance_type

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.app_server.id]
    ipv6_address_count          = 1
  }

  iam_instance_profile {
    name = var.instance_profile_name
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y nginx
    systemctl start nginx
    systemctl enable nginx
    echo "<h1>Hello from $(hostname -f)</h1>" > /var/www/html/index.html
    EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_prefix}-app-server"
      Environment = var.environment
      Project     = var.project_prefix
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true
  }

  tags = {
    Name        = "${var.project_prefix}-app-lt"
    Environment = var.environment
    Project     = var.project_prefix
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app" {
  name                      = "${var.project_prefix}-app-asg"
  vpc_zone_identifier       = data.terraform_remote_state.networking.outputs.private_subnet_ids
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  min_size         = 2
  max_size         = var.asg_max_size
  desired_capacity = 2

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_prefix}-app-asg"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_prefix
    propagate_at_launch = true
  }
}
