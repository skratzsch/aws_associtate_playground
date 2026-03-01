# Packer – Cattle Golden AMI

Builds an immutable AMI with NGINX + NextJS pre-installed and ready to serve.
No configuration happens at launch — instances are fully baked and start serving traffic
within seconds of boot. This is the **cattle counterpart** to the Ansible/SSM pet setup.

## Directory Structure

```
packer/
├── cattle.pkr.hcl       # Packer HCL template (AMI definition)
└── scripts/
    └── setup.sh         # Provisioner script: installs and configures everything
```

## How It Works

### Pet vs. Cattle

| | Pet (`03-compute-pet`) | Cattle (`03-compute`) |
|---|---|---|
| Instances | 1, named, long-lived | N, anonymous, disposable |
| Config | Ansible via SSM after launch | Baked into the AMI at build time |
| Launch time | Fast (config takes ~5 min) | Fast (fully pre-configured) |
| Update | Re-run Ansible playbook | Build new AMI, rolling replace in ASG |

### What Gets Baked Into the AMI

1. NGINX — installed and configured as reverse proxy (port 80 → 3000)
2. Node.js LTS — via NodeSource
3. `on-the-run-web` — cloned from GitHub, `npm ci`, `npm run build`
4. systemd services for both NGINX and NextJS — **enabled, not started**
   (they start automatically on first boot)

The `user_data` in `03-compute` is intentionally minimal — it only ensures the SSM agent
is running. Everything else is already in the AMI.

### Hash-Based Build Cache

The `build-ami` pipeline avoids unnecessary rebuilds:

1. Compute a SHA256 hash over all files in `packer/`
2. Check if an AMI with tag `packer_hash=<hash>` already exists
3. If yes → skip build, reuse the existing AMI
4. If no → run `packer build`, tag the new AMI with the hash

**Fallback chain** (if the build fails):
1. AMI with matching hash → use it (no build needed)
2. Fresh Packer build → use the new AMI
3. Build failed → use any AMI tagged `status=latest`
4. No latest tag → use the most recently created `tuwa-cattle-*` AMI
5. Nothing found → pipeline fails

The hash changes only when Packer files or scripts change — **not** when the app repo
gets new commits. A code-only update requires a manual pipeline trigger or a touch to
any file in `packer/`.

## Pipelines

| Workflow | Trigger | What it does |
|---|---|---|
| `build-ami.yml` | `workflow_dispatch` or called from `create-cattle` | Hash check → build → output AMI ID |
| `create-cattle.yml` | `workflow_dispatch` | `build-ami` + `networking` in parallel → `security` → `compute` |
| `destroy-ami.yml` | `workflow_dispatch` | Deregister AMIs + delete snapshots |
| `terraform-destroy.yml` | `workflow_dispatch` | Destroy Terraform infrastructure |

## Required IAM Permissions

The `github-actions-terraform` IAM role needs the following **in addition** to existing
Terraform permissions:

```json
{
  "Effect": "Allow",
  "Action": [
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
  ],
  "Resource": "*"
}
```

Add this as an inline policy to the `github-actions-terraform` role in
`terraform/02-security/main.tf`.

## Running Locally

Requires: `packer`, `aws-cli`, credentials with the permissions listed above.

```bash
# Get a public subnet ID from existing networking state
SUBNET_ID=$(aws s3 cp \
  s3://aws-associate-playground-terraform-state/dev/networking/terraform.tfstate - \
  | jq -r '.outputs.public_subnet_ids.value[0]')

cd packer/
packer init .
packer build \
  -var "subnet_id=$SUBNET_ID" \
  -var "packer_hash=local-dev" \
  cattle.pkr.hcl
```
