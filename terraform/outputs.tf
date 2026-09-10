output "instance_public_ip" {
  value = aws_instance.app.public_ip
}

output "instance_id" {
  value = aws_instance.app.id
}

output "ssh_command" {
  value = "ssh -i ${var.project_name}-key.pem ubuntu@${aws_instance.app.public_ip}"
}

output "gateway_url" {
  value = "https://${aws_instance.app.public_ip}:3000"
}

output "vault_url" {
  value = "https://${aws_instance.app.public_ip}:8200"
}

output "private_key_path" {
  value = local_sensitive_file.private_key.filename
}
