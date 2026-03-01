# Ansible – SSM Showcase

Deploys NGINX + NextJS to a single EC2 instance (pet-style) via AWS SSM Session Manager.
No SSH, no bastion, no open ports. The connection runs entirely through SSM.

## Directory Structure

```
ansible/
├── ansible.cfg
├── inventory/
│   └── aws_ec2.yml          # Dynamic inventory (filters by tag deployment_type=pet)
└── playbooks/
    ├── site.yml              # Entry point
    ├── nginx.yml             # Install NGINX + configure reverse proxy
    ├── nextjs.yml            # Node.js + clone app + build + systemd service
    ├── group_vars/
    │   └── all.yml           # SSM connection config + repo URL
    └── templates/
        ├── nginx.conf.j2     # Reverse proxy: port 80 → 3000
        └── nextjs.service.j2 # systemd service definition
```

## Prerequisites

On the control node (GitHub Actions runner):
- `ansible`, `boto3`, `botocore`
- Collections: `amazon.aws`, `community.aws`
- AWS Session Manager Plugin (`session-manager-plugin`)

On the EC2 instance:
- SSM Agent running
- IAM role with `AmazonSSMManagedInstanceCore`
- S3 access to the Ansible temp bucket (via bucket policy in `03-compute-pet`)

## Running

```bash
ansible-playbook playbooks/site.yml \
  -e "ansible_aws_ssm_bucket_name=<bucket-name>"
```

---

## Debugging Log – Known Errors During Setup

A chronological record of all errors encountered during the setup.
Useful as a reference when re-setting up the environment.

---

### 1. Deprecated `yaml` Callback Plugin

**Error:**
```
Error: The 'community.general.yaml' callback plugin has been removed.
```

**Cause:**
`stdout_callback = yaml` in `ansible.cfg` pulls in `community.general.yaml`, which was
removed in community.general 12.0.0.

**Fix in `ansible.cfg`:**
```ini
# Before
stdout_callback = yaml

# After
stdout_callback = default
result_format   = yaml
```

---

### 2. Ansible Connects via SSH Instead of SSM

**Error:**
```
Failed to connect to the host via ssh: ssh: Could not resolve hostname i-0abc123:
Temporary failure in name resolution
```

**Cause:**
Ansible looks for `group_vars` relative to the playbook or inventory file — not in the
parent directory. `ansible/group_vars/all.yml` was being ignored.

Ansible searches:
- `playbooks/group_vars/` ✓
- `inventory/group_vars/` ✓
- `group_vars/` ✗ (not found)

**Fix:**
Move `group_vars/` to `playbooks/group_vars/`.

---

### 3. SSM Connection: NoneType Error During Gathering Facts

**Error:**
```
Task failed: expected string or bytes-like object, got 'NoneType'
```

**Cause:**
The `amazon.aws.aws_ssm` connection plugin requires an S3 bucket to transfer temporary
files (Ansible modules, templates) to the EC2 instance. Without a bucket the plugin
crashes on the first file transfer.

**Fix:**
Create an S3 bucket in `03-compute-pet`. The bucket name is passed via Terraform output
from the `compute-pet` job to the `ansible` job in the pipeline:

```yaml
- name: Run Ansible playbook
  run: ansible-playbook playbooks/site.yml \
    -e "ansible_aws_ssm_bucket_name=${{ needs.compute-pet.outputs.ansible_bucket_name }}"
```

---

### 4. `become_user` Fails: setfacl Not Available

**Error:**
```
Failed to set permissions on the temporary files Ansible needs to create
when becoming an unprivileged user (rc: 1, err: )
```

**Cause:**
Ansible uses `setfacl` when switching users (`become_user`). The `acl` package that
provides `setfacl` is not installed by default on Ubuntu.

**Fix in `nextjs.yml`:**
```yaml
- name: Install acl (required for become_user)
  ansible.builtin.apt:
    name: acl
    state: present
```

---

### 5. Git Clone Fails: Permission Denied in `/opt/`

**Error:**
```
fatal: could not create work tree dir '/opt/on-the-run-web': Permission denied
```

**Cause:**
`/opt/` is owned by root. The `ubuntu` user (via `become_user`) cannot create
directories there.

**Fix in `nextjs.yml`:**
Create the directory first as root so the `ubuntu` user has write access:
```yaml
- name: Create app directory
  ansible.builtin.file:
    path: "{{ app_dir }}"
    state: directory
    owner: "{{ app_user }}"
    group: "{{ app_user }}"
    mode: "0755"
```

---

### 6. Deprecated Connection Plugin Name

**Background:**
`community.aws.aws_ssm` was migrated to `amazon.aws.aws_ssm` and is deprecated.

**Fix in `group_vars/all.yml`:**
```yaml
# Before
ansible_connection: community.aws.aws_ssm

# After
ansible_connection: amazon.aws.aws_ssm
```

---

### 7. New S3 Bucket: HTTP 307 Redirect

**Background:**
The SSM plugin creates S3 presigned URLs. For newly created buckets (< ~1h old)
S3 responds with an HTTP 307 due to DNS propagation. `curl` on the EC2 instance does
not follow this redirect, causing the download to fail silently.

Since the bucket is created in the same pipeline run, this will always affect us.

**Fix in `group_vars/all.yml`:**
```yaml
ansible_aws_ssm_s3_addressing_style: path
```

This uses `s3.amazonaws.com/bucket/key` instead of `bucket.s3.amazonaws.com/key`
— no DNS issue.
