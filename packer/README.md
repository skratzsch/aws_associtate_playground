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
| `build-ami.yml` | `workflow_dispatch` | `networking` → `security` → packer build → AMI ID output |
| `create-cattle.yml` | `workflow_dispatch` | `build-ami` → `compute` (uses AMI ID from build-ami) |
| `destroy-ami.yml` | `workflow_dispatch` | Deregister AMIs + delete snapshots |
| `terraform-destroy.yml` | `workflow_dispatch` | Destroy Terraform infrastructure |

`build-ami.yml` is self-contained — it always applies `01-networking` and `02-security`
first, so it can be triggered standalone without manual preparation.

## Running Locally

Requires: `packer`, `aws-cli`, `session-manager-plugin`, credentials with Packer permissions.

```bash
SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=tag:Project,Values=tuwa" "Name=tag:Type,Values=public" \
  --query 'Subnets[0].SubnetId' --output text)

PROFILE_NAME=$(aws iam list-instance-profiles \
  --query "InstanceProfiles[?InstanceProfileName=='tuwa-ec2-instance-profile'].InstanceProfileName | [0]" \
  --output text)

cd packer/
packer init .
packer build \
  -var "subnet_id=$SUBNET_ID" \
  -var "instance_profile_name=$PROFILE_NAME" \
  -var "packer_hash=local-dev" \
  cattle.pkr.hcl
```

---

## Debugging Log – Known Errors During Setup

---

### 1. Silent failure — "No AMI available and build failed"

**Error:**
```
Packer build failed or no AMI ID — falling back to latest tagged AMI...
No latest-tagged AMI — falling back to most recent tuwa-cattle-* AMI...
ERROR: No AMI available and build failed. Cannot continue.
```

**Cause:**
Packer failed silently. `packer build | tee` passes the exit code of `tee` (always 0),
not Packer's exit code. The actual Packer error was never surfaced.

**Fix:**
Use `${PIPESTATUS[0]}` to capture Packer's exit code through the pipe:
```bash
packer build -machine-readable cattle.pkr.hcl | tee /tmp/packer-output.txt
PACKER_EXIT=${PIPESTATUS[0]}
```

---

### 2. SSH timeout — Packer can't connect to build instance

**Cause:**
Packer's default communicator is SSH. It tries to connect on port 22 from the
GitHub Actions runner (Azure IP) to the EC2 build instance (AWS). This times out
silently after 5 minutes because runner IPs rotate constantly and can't be
whitelisted reliably.

**Fix in `cattle.pkr.hcl`:**
```hcl
communicator         = "ssh"
ssh_interface        = "session_manager"
ssh_username         = "ubuntu"
iam_instance_profile = var.instance_profile_name
```
Packer tunnels through SSM — no open ports, no IP allowlisting needed.
Requires `session-manager-plugin` on the runner and `AmazonSSMManagedInstanceCore`
on the build instance's IAM profile.

---

### 3. Subnet ID 'null'

**Error:**
```
InvalidSubnetID.NotFound: The subnet ID 'null' does not exist.
```

**Cause:**
The subnet ID was read from the Terraform state file via `aws s3 cp ... | jq`.
The S3 state file didn't exist yet (first run) or the pipe produced unreliable output.

**Fix:**
Query the EC2 API directly instead of parsing state:
```bash
SUBNET_ID=$(aws ec2 describe-subnets \
  --filters \
    "Name=tag:Project,Values=tuwa" \
    "Name=tag:Type,Values=public" \
    "Name=tag:Environment,Values=dev" \
  --query 'Subnets[0].SubnetId' \
  --output text)
```

---

### 4. Instance Profile not found

**Error:**
```
NoSuchEntity: Instance Profile tuwa-ec2-instance-profile cannot be found.
```

**Cause 1:** `build-ami.yml` was triggered directly (via `workflow_dispatch`) without
`02-security` having been applied first. The instance profile didn't exist in IAM yet.

**Fix:** Made `build-ami.yml` self-contained — it applies `01-networking` and
`02-security` before running Packer. No manual preparation needed.

**Cause 2:** The instance profile name was read from the S3 state file via `aws s3 cp | jq`,
which returned `null` even though the security apply had just run.

**Fix:** Read the profile name via `terraform output -raw` directly in the `security` job
after apply, and pass it as a job output to the `build` job:
```yaml
- name: Get instance profile name
  id: tf_output
  run: echo "instance_profile_name=$(terraform output -raw ec2_instance_profile_name)" >> $GITHUB_OUTPUT
```

---

### 5. Missing IAM permissions for Packer

**Cause:**
The `github-actions-terraform` role lacked EC2 permissions for Packer
(RunInstances, CreateImage, CreateSecurityGroup, CreateKeyPair, etc.) and
IAM permissions (`iam:PassRole`, `iam:GetInstanceProfile`) needed to attach
an instance profile to the build instance.

**Fix in `02-security/main.tf`:**
Added `aws_iam_role_policy.github_actions_packer` with all required EC2 and IAM
permissions, plus SSM session permissions (`ssm:StartSession`, `ssm:TerminateSession`,
`ssm:GetConnectionStatus`) for the SSM communicator.

---

### 6. `build-ami` ran before `02-security` permissions were applied

**Cause:**
In the original `create-cattle.yml`, `build-ami` and `networking` ran in parallel.
`security` ran after networking — but the Packer IAM permissions are applied by
`security`. So `build-ami` started without the required permissions.

**Fix:**
`build-ami.yml` is now self-contained and runs `networking` → `security` → `build`
sequentially within the same workflow. Job ordering is guaranteed.

---

### 8. AMI rebuilt every run despite existing AMI

**Cause:**
The hash was computed over all files in `packer/` including `README.md`:
```bash
find packer/ -type f | sort | xargs sha256sum | ...
```
Any documentation change produces a different hash → existing AMI tag doesn't match →
cache miss → Packer rebuilds unnecessarily.

**Fix:**
Only hash files that actually affect the build (`.hcl` and `.sh`):
```bash
find packer/ -type f \( -name "*.hcl" -o -name "*.sh" \) | sort | xargs sha256sum | ...
```
README changes no longer trigger a rebuild.

---

### 7. Script not running as root — permission errors during apt-get / systemd

**Cause:**
With the SSM communicator, Packer connects as `ubuntu` (the `ssh_username`). The
provisioner shell script runs as that user by default — no root access, `apt-get` and
`systemctl` fail.

**Fix in `cattle.pkr.hcl`:**
```hcl
provisioner "shell" {
  script          = "scripts/setup.sh"
  execute_command = "sudo bash '{{.Path}}'"
}
```
The `execute_command` override runs the script as root via sudo. The `sudo -u ubuntu`
block inside `setup.sh` for git clone + npm build is intentional and stays — the app
should be owned by the `ubuntu` user, not root.

---
