# =============================================================================
# KMS module — outputs
# =============================================================================

output "key_id" {
  description = "The KMS key ID."
  value       = aws_kms_key.this.key_id
}

output "key_arn" {
  description = "The KMS key ARN."
  value       = aws_kms_key.this.arn
}

output "alias_name" {
  description = "The KMS alias name."
  value       = aws_kms_alias.this.name
}
