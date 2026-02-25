# AWS Associate Playground

Hands-on infrastructure for AWS Solution Architect Associate exam preparation.
Built with Terraform, deployed via GitHub Actions to `eu-central-1`.

## Architecture

Five Terraform modules deployed in dependency order:

| Module | Resources |
|--------|-----------|
| `01-networking` | VPC (IPv4 + IPv6), public/private subnets, IGW, Egress-Only IGW |
| `02-security` | KMS, Secrets Manager, IAM roles for EC2 |
| `03-compute` | ALB (dualstack), Auto Scaling Group, Launch Template (nginx) |
| `04-storage` | EFS (encrypted), AWS Backup |
| `05-database` | RDS PostgreSQL 15 (Multi-AZ, encrypted), SSM Parameter Store |

**Design decisions:**
- No NAT Gateway — private subnets use Egress-Only IGW for IPv6 outbound. Ubuntu apt works natively over IPv6.
- EC2 instances use SSM Session Manager instead of SSH (no port 22).
- IMDSv2 enforced on all instances.
- DB credentials stored in Github Actions Secrets and injected via SSM Parameter Store.

## CI/CD

Two GitHub Actions workflows:

**`terraform.yml`** — triggered on push to `main` or PR touching `terraform/**`
- Detects changed modules (PR) or runs all modules in order (push to main)
- Steps per module: `fmt` → `init` → `validate` → `plan` → `apply`
- PRs get a plan comment, apply only runs on main

**`terraform-destroy.yml`** — manual trigger (`workflow_dispatch`)
- Select a single module or `all`
- Destroy order: `05 → 04 → 03 → 02 → 01`

## Remote State

Terraform state is stored in S3:

```
Bucket: aws-associate-playground-terraform-state
Region: eu-central-1
Keys:   dev/networking/terraform.tfstate
        dev/compute/terraform.tfstate
        dev/storage/terraform.tfstate
        dev/database/terraform.tfstate
        dev/security/terraform.tfstate
```

## Local Development

### Prerequisites

- Terraform >= 1.0
- AWS CLI v2 with valid credentials
- Access to the state bucket

### Run a plan locally

```bash
cd terraform/05-database
terraform init
terraform plan -var="db_password=<your-password>"
```

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `DB_PASSWORD` | Master password for the RDS PostgreSQL instance |

## Cost Management

Always destroy resources after use to avoid unnecessary charges:

1. Go to **Actions** → **Terraform Destroy**
2. Select `all` or the specific module
3. Run workflow

RDS Multi-AZ and EFS are the main cost drivers.