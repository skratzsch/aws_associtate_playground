# 05-security

Security & IAM Module für AWS Associate Playground.

## Komponenten

- **IAM Role für EC2**: SSM Session Manager + CloudWatch Logs + Secrets Manager
- **IAM Instance Profile**: Für EC2 Launch Template
- **KMS Key**: Verschlüsselung für Secrets Manager
- **Secrets Manager**: GitHub Token (Placeholder - manuell setzen)

## Deployment

```bash
terraform init
terraform plan
terraform apply
```

## GitHub Token manuell setzen

Nach dem Deployment:

```bash
aws secretsmanager put-secret-value \
  --secret-id tuwa-github-token \
  --secret-string '{"token":"ghp_YOUR_TOKEN_HERE"}' \
  --region eu-central-1
```

## Outputs

- `ec2_instance_profile_name`: Für 02-compute Launch Template
- `github_token_secret_arn`: Für Ansible/Deployment Scripts
- `kms_key_arn`: Für zusätzliche Secrets

