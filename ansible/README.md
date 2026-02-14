# Ansible Playbooks

This directory contains Ansible playbooks and roles for AWS configuration management.

## Structure

Organize your Ansible code:
- `playbooks/` - Ansible playbooks
- `roles/` - Custom Ansible roles
- `inventory/` - Inventory files (use example templates)
- `group_vars/` - Group variables
- `host_vars/` - Host-specific variables

## Usage

1. Configure your inventory file
2. Run a playbook:
   ```bash
   ansible-playbook -i inventory/hosts playbook.yml
   ```
3. Test connectivity:
   ```bash
   ansible all -i inventory/hosts -m ping
   ```

## Best Practices

- Use Ansible Vault for sensitive data
- Create reusable roles
- Use dynamic inventory for AWS
- Tag your plays and tasks
- Use variables for flexibility
