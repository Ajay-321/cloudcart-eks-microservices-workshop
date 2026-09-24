# =============================================================================
# DynamoDB module — outputs
# =============================================================================

output "table_names" {
  description = "Map of table keys to table names"
  value = {
    for k, v in aws_dynamodb_table.tables : k => v.name
  }
}

output "table_ids" {
  description = "Map of table keys to table IDs"
  value = {
    for k, v in aws_dynamodb_table.tables : k => v.id
  }
}

output "table_arns" {
  description = "Map of table keys to table ARNs"
  value = {
    for k, v in aws_dynamodb_table.tables : k => v.arn
  }
}

output "table_arns_list" {
  description = "List of all table ARNs (handy for IAM policies)"
  value       = [for k, v in aws_dynamodb_table.tables : v.arn]
}

output "table_stream_arns" {
  description = "Map of table keys to stream ARNs (if streams are enabled)"
  value = {
    for k, v in aws_dynamodb_table.tables : k => v.stream_arn
    if v.stream_arn != null
  }
}

output "table_stream_labels" {
  description = "Map of table keys to stream labels (if streams are enabled)"
  value = {
    for k, v in aws_dynamodb_table.tables : k => v.stream_label
    if v.stream_label != null
  }
}

# Backward compatibility outputs (for single table use case)
output "table_name" {
  description = "The name of the first DynamoDB table (for backward compatibility)"
  value       = try(values(aws_dynamodb_table.tables)[0].name, null)
}

output "table_id" {
  description = "The ID of the first DynamoDB table (for backward compatibility)"
  value       = try(values(aws_dynamodb_table.tables)[0].id, null)
}

output "table_arn" {
  description = "The ARN of the first DynamoDB table (for backward compatibility)"
  value       = try(values(aws_dynamodb_table.tables)[0].arn, null)
}
