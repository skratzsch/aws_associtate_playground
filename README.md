# AWS Associate Playground

Hands-on infrastructure for AWS Solution Architect Associate exam preparation.
Built with Terraform, deployed via GitHub Actions to `eu-central-1`.

## Architecture

### Terraform Modules

| Module | Resources |
|--------|-----------|
| `01-networking` | VPC (IPv4 + IPv6), public/private subnets, IGW, Egress-Only IGW |
| `02-security` | KMS, Secrets Manager, IAM roles for EC2 |
| `03-compute` | ALB (dualstack), Auto Scaling Group, Launch Template |
| `03-compute-pet` | Single EC2 in public subnet — Ansible showcase |
| `04-storage` | EFS (encrypted), AWS Backup |
| `05-database` | RDS PostgreSQL 15 (Multi-AZ, encrypted), SSM Parameter Store |

**Design decisions:**
- No NAT Gateway — private subnets use Egress-Only IGW for IPv6 outbound. Ubuntu apt works natively over IPv6.
- EC2 instances use SSM Session Manager instead of SSH (no port 22).
- IMDSv2 enforced on all instances.
- DB credentials stored in Github Actions Secrets and injected via SSM Parameter Store.

## Deployment Variants

### Pet (Ansible)

Single EC2 instance in a public subnet. Ansible runs from GitHub Actions via SSM Session Manager — no SSH, no bastion.

Stack: NGINX → NextJS (port 3000), deployed as a systemd service.

```
networking → security → compute-pet → ansible
```

### Cattle (coming soon)

Packer builds a custom AMI with the full stack baked in. Auto Scaling Group uses the AMI. No configuration on running instances.

## CI/CD

**`create-pet.yml`** — manual trigger (`workflow_dispatch`)
- Deploys: `01-networking` → `02-security` → `03-compute-pet`
- Then runs Ansible: installs NGINX, clones and builds NextJS, starts systemd service

**`terraform.yml`** — manual trigger (`workflow_dispatch`) or PR touching `terraform/**`
- Full stack: all five modules in dependency order
- PRs get a plan comment per module

**`terraform-destroy.yml`** — manual trigger (`workflow_dispatch`)
- Select a single module or `all`
- Destroy order: `05 → 04 → 03-compute → 03-compute-pet → 02 → 01`

## Ansible

Located in `ansible/`. Connects to EC2 via SSM Session Manager using the `amazon.aws.aws_ssm` connection plugin — no IP addresses, no open ports.

Dynamic inventory via `amazon.aws.aws_ec2` plugin filters by tag `deployment_type: pet`.

```
ansible/
├── ansible.cfg
├── inventory/aws_ec2.yml            # dynamic inventory (tag: deployment_type=pet)
└── playbooks/
    ├── site.yml                     # entry point
    ├── nginx.yml                    # installs and configures NGINX
    ├── nextjs.yml                   # clones repo, builds and runs NextJS
    ├── group_vars/all.yml           # SSM connection config + repo URL
    └── templates/
        ├── nginx.conf.j2            # reverse proxy: port 80 → 3000
        └── nextjs.service.j2        # systemd service definition
```

See [`ansible/README.md`](ansible/README.md) for setup details and a full debugging log of known SSM issues.

## Remote State

Terraform state is stored in S3:

```
Bucket: aws-associate-playground-terraform-state
Region: eu-central-1
Keys:   dev/networking/terraform.tfstate
        dev/security/terraform.tfstate
        dev/compute/terraform.tfstate
        dev/compute-pet/terraform.tfstate
        dev/storage/terraform.tfstate
        dev/database/terraform.tfstate
```

## Bootstrap

Run once before the first pipeline execution:

```bash
python3 scripts/bootstrap_terraform_backend.py   # S3 bucket + DynamoDB lock table
python3 scripts/bootstrap_github_oidc.py          # OIDC provider + GitHub Actions IAM role
```

## Local Development

Prerequisites: Terraform >= 1.0, AWS CLI v2, access to the state bucket.

```bash
cd terraform/03-compute-pet
terraform init
terraform plan
```

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `DB_PASSWORD` | Master password for the RDS PostgreSQL instance |

## Cost Management

Always destroy resources after use:

1. Go to **Actions** → **Terraform Destroy**
2. Select `all` or the specific module
3. Run workflow

Main cost drivers: RDS Multi-AZ, EFS, ALB.
Pet EC2 (t3.micro + public IPv4): ~$0.015/hour while running.
