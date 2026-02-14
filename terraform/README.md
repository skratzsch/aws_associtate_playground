# Terraform Configurations

This directory contains Terraform configurations for provisioning AWS resources.

## Structure

Organize your Terraform code by AWS service or use case:
- `ec2/` - EC2 instances and related resources
- `vpc/` - VPC, subnets, route tables
- `s3/` - S3 buckets and configurations
- `rds/` - RDS database instances
- `lambda/` - Lambda functions
- etc.

## Usage

1. Navigate to a specific module directory
2. Initialize Terraform:
   ```bash
   terraform init
   ```
3. Plan your changes:
   ```bash
   terraform plan
   ```
4. Apply the configuration:
   ```bash
   terraform apply
   ```
5. Clean up resources:
   ```bash
   terraform destroy
   ```

## Best Practices

- Use variables for reusable configurations
- Store sensitive data in `terraform.tfvars` (gitignored)
- Use remote state for team collaboration
- Tag all resources appropriately
- Always run `terraform destroy` after practice
