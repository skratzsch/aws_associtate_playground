# Ansible – SSM Showcase

Deploys NGINX + NextJS auf eine einzelne EC2 Instanz (Pet-Style) via AWS SSM Session Manager.
Kein SSH, kein Bastion, keine offenen Ports. Verbindung läuft komplett über SSM.

## Verzeichnisstruktur

```
ansible/
├── ansible.cfg
├── inventory/
│   └── aws_ec2.yml          # Dynamic inventory (filtert nach tag deployment_type=pet)
└── playbooks/
    ├── site.yml              # Einstiegspunkt
    ├── nginx.yml             # NGINX installieren + Reverse Proxy konfigurieren
    ├── nextjs.yml            # Node.js + App clonen + bauen + systemd Service
    ├── group_vars/
    │   └── all.yml           # SSM Connection Config + Repo URL
    └── templates/
        ├── nginx.conf.j2     # Reverse Proxy: Port 80 → 3000
        └── nextjs.service.j2 # systemd Service Definition
```

## Voraussetzungen

Auf dem Control Node (GitHub Actions Runner):
- `ansible`, `boto3`, `botocore`
- Collections: `amazon.aws`, `community.aws`
- AWS Session Manager Plugin (`session-manager-plugin`)

Auf der EC2:
- SSM Agent läuft
- IAM Role mit `AmazonSSMManagedInstanceCore`
- S3 Zugriff auf den Ansible-Temp-Bucket (via Bucket Policy in `03-compute-pet`)

## Ausführen

```bash
ansible-playbook playbooks/site.yml \
  -e "ansible_aws_ssm_bucket_name=<bucket-name>"
```

---

## Debugging Log – Bekannte Fehler beim Aufbau

Eine chronologische Dokumentation aller Fehler die beim Aufbau aufgetreten sind.
Hilfreich als Referenz wenn das Setup neu aufgesetzt wird.

---

### 1. Deprecated `yaml` Callback Plugin

**Fehler:**
```
Error: The 'community.general.yaml' callback plugin has been removed.
```

**Ursache:**
`stdout_callback = yaml` in `ansible.cfg` zieht `community.general.yaml`, das in
community.general 12.0.0 entfernt wurde.

**Fix in `ansible.cfg`:**
```ini
# Vorher
stdout_callback = yaml

# Nachher
stdout_callback = default
result_format   = yaml
```

---

### 2. Ansible verbindet via SSH statt SSM

**Fehler:**
```
Failed to connect to the host via ssh: ssh: Could not resolve hostname i-0abc123:
Temporary failure in name resolution
```

**Ursache:**
Ansible sucht `group_vars` relativ zum Playbook oder zur Inventory-Datei — nicht im
übergeordneten Verzeichnis. `ansible/group_vars/all.yml` wurde ignoriert.

Ansible sucht:
- `playbooks/group_vars/` ✓
- `inventory/group_vars/` ✓
- `group_vars/` ✗ (wird nicht gefunden)

**Fix:**
`group_vars/` nach `playbooks/group_vars/` verschieben.

---

### 3. SSM Connection: NoneType Fehler bei Gathering Facts

**Fehler:**
```
Task failed: expected string or bytes-like object, got 'NoneType'
```

**Ursache:**
Das `amazon.aws.aws_ssm` Connection Plugin benötigt zwingend einen S3 Bucket um
temporäre Dateien (Ansible Module, Templates) zur EC2 zu übertragen. Ohne Bucket
crasht das Plugin beim ersten File Transfer.

**Fix:**
S3 Bucket in `03-compute-pet` erstellen. Bucket Name wird via Terraform Output aus
dem `compute-pet` Job an den `ansible` Job der Pipeline weitergereicht:

```yaml
- name: Run Ansible playbook
  run: ansible-playbook playbooks/site.yml \
    -e "ansible_aws_ssm_bucket_name=${{ needs.compute-pet.outputs.ansible_bucket_name }}"
```

---

### 4. `become_user` schlägt fehl: setfacl nicht verfügbar

**Fehler:**
```
Failed to set permissions on the temporary files Ansible needs to create
when becoming an unprivileged user (rc: 1, err: )
```

**Ursache:**
Ansible nutzt `setfacl` wenn es den User wechselt (`become_user`). Das Paket `acl`
das `setfacl` bereitstellt ist auf Ubuntu nicht standardmäßig installiert.

**Fix in `nextjs.yml`:**
```yaml
- name: Install acl (required for become_user)
  ansible.builtin.apt:
    name: acl
    state: present
```

---

### 5. Git Clone schlägt fehl: Permission denied in `/opt/`

**Fehler:**
```
fatal: could not create work tree dir '/opt/on-the-run-web': Permission denied
```

**Ursache:**
`/opt/` gehört root. Der `ubuntu` User (via `become_user`) kann dort kein
Verzeichnis anlegen.

**Fix in `nextjs.yml`:**
Verzeichnis vorher als root erstellen, dann hat `ubuntu` Schreibzugriff:
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

**Hintergrund:**
`community.aws.aws_ssm` wurde nach `amazon.aws.aws_ssm` migriert und ist deprecated.

**Fix in `group_vars/all.yml`:**
```yaml
# Vorher
ansible_connection: community.aws.aws_ssm

# Nachher
ansible_connection: amazon.aws.aws_ssm
```

---

### 7. Neuer S3 Bucket: HTTP 307 Redirect

**Hintergrund:**
Das SSM Plugin erstellt S3 Presigned URLs. Bei neu erstellten Buckets (< ~1h alt)
antwortet S3 mit einem HTTP 307 wegen DNS-Propagation. `curl` auf der EC2 folgt
diesem Redirect nicht, der Download schlägt lautlos fehl.

Da der Bucket im selben Pipeline-Run erstellt wird, trifft uns das garantiert.

**Fix in `group_vars/all.yml`:**
```yaml
ansible_aws_ssm_s3_addressing_style: path
```

Damit wird `s3.amazonaws.com/bucket/key` statt `bucket.s3.amazonaws.com/key`
verwendet — kein DNS-Problem mehr.
