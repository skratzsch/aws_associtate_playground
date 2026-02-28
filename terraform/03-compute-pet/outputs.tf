output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.pet.id
}

output "public_ip" {
  description = "Public IP of the Pet EC2 instance"
  value       = aws_instance.pet.public_ip
}

output "public_dns" {
  description = "Public DNS of the Pet EC2 instance"
  value       = aws_instance.pet.public_dns
}

output "ansible_bucket_name" {
  description = "S3 bucket name for Ansible SSM temporary files"
  value       = aws_s3_bucket.ansible_tmp.bucket
}