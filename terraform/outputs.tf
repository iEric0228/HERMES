output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.hermes.id
}

output "public_ip" {
  description = "Elastic IP address"
  value       = aws_eip.hermes.public_ip
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_eip.hermes.public_ip}"
}

output "dashboard_tunnel" {
  description = "SSH tunnel for Hermes dashboard (run locally, then open http://localhost:9119)"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem -L 9119:localhost:9119 ubuntu@${aws_eip.hermes.public_ip}"
}

output "backup_bucket" {
  description = "S3 backup bucket name"
  value       = aws_s3_bucket.backup.id
}

output "data_volume_id" {
  description = "EBS data volume ID (survives instance termination)"
  value       = aws_ebs_volume.data.id
}

output "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  value       = aws_sns_topic.alerts.arn
}
