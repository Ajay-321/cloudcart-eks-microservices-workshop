output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "region" {
  value = var.region
}

output "ecr_repository_urls" {
  description = "Push your images to these URLs."
  value       = module.ecr.repository_urls
}

output "dynamodb_table_arns" {
  value = var.enable_dynamodb ? module.dynamodb[0].table_arns : {}
}

output "pod_identity_role_arn" {
  value = var.enable_dynamodb ? module.pod_identity[0].role_arn : null
}

# Handy: the exact command to configure kubectl after apply.
output "configure_kubectl" {
  description = "Run this to point kubectl at the new cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
