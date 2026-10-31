output "public_ip" {
  description = "Elastic IP — stable across stop/start"
  value       = aws_eip.ci.public_ip
}

output "jenkins_url" {
  description = "Jenkins, once make deploy has run"
  value       = "http://${aws_eip.ci.public_ip}:8080"
}

output "sonarqube_url" {
  description = "SonarQube, once make deploy has run"
  value       = "http://${aws_eip.ci.public_ip}:9000"
}

output "ssh_command" {
  description = "Shell on the instance"
  value       = "ssh -i ${var.ssh_private_key_path} ubuntu@${aws_eip.ci.public_ip}"
}

output "instance_id" {
  description = "For make pause and make resume"
  value       = aws_instance.ci.id
}

output "region" {
  description = "Region, read back by the Makefile's aws CLI calls"
  value       = var.region
}

output "github_webhook_url" {
  description = "Where GitHub delivers push and pull request events — make webhooks registers it"
  value       = "http://${aws_eip.ci.public_ip}:8080/github-webhook/"
}
