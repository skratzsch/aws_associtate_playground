output "efs_id" {
  description = "EFS File System ID"
  value       = aws_efs_file_system.main.id
}

output "efs_dns_name" {
  description = "EFS DNS name for mounting"
  value       = aws_efs_file_system.main.dns_name
}

output "efs_arn" {
  description = "EFS File System ARN"
  value       = aws_efs_file_system.main.arn
}

output "efs_security_group_id" {
  description = "Security Group ID for EFS"
  value       = aws_security_group.efs.id
}

output "mount_target_ids" {
  description = "EFS Mount Target IDs"
  value       = aws_efs_mount_target.main[*].id
}

output "mount_target_dns_names" {
  description = "EFS Mount Target DNS names"
  value       = aws_efs_mount_target.main[*].dns_name
}

output "backup_vault_name" {
  description = "AWS Backup Vault name"
  value       = aws_backup_vault.efs_vault.name
}

output "backup_plan_id" {
  description = "AWS Backup Plan ID"
  value       = aws_backup_plan.efs_backup.id
}

