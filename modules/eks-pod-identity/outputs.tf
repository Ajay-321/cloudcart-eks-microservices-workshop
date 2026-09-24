# =============================================================================
# EKS Pod Identity module — outputs
# =============================================================================

output "role_arn" {
  description = "ARN of the IAM role bound to the service account."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the IAM role bound to the service account."
  value       = aws_iam_role.this.name
}
