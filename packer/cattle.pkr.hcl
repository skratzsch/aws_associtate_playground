packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "base_ami_id" {
  type        = string
  default     = "ami-0084a47cc718c111a" # Ubuntu 22.04 LTS eu-central-1
  description = "Base AMI to build from"
}

variable "subnet_id" {
  type        = string
  description = "Public subnet ID for the Packer build instance"
}

variable "packer_hash" {
  type        = string
  default     = ""
  description = "Hash of packer files, stored as AMI tag for cache lookup"
}

locals {
  timestamp = regex_replace(timestamp(), "[: TZ]", "")
}

source "amazon-ebs" "cattle" {
  region        = var.region
  source_ami    = var.base_ami_id
  instance_type = "t3.small"
  ssh_username  = "ubuntu"
  subnet_id     = var.subnet_id

  ami_name                    = "tuwa-cattle-${local.timestamp}"
  associate_public_ip_address = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name        = "tuwa-cattle"
    status      = "latest"
    packer_hash = var.packer_hash
    Project     = "tuwa"
    Environment = "dev"
    BuiltBy     = "packer"
  }
}

build {
  name    = "tuwa-cattle"
  sources = ["source.amazon-ebs.cattle"]

  provisioner "shell" {
    script = "scripts/setup.sh"
  }
}
