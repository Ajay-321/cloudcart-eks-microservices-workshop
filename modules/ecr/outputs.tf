# =============================================================================
# ECR module — outputs
# =============================================================================

output "repository_urls" {
  description = "Map of repo name -> repository URL (use these in k8s image refs)."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repository_arns" {
  description = "Map of repo name -> repository ARN."
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
}
