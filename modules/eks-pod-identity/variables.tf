# =============================================================================
# EKS Pod Identity module — inputs
# =============================================================================

variable "cluster_name" {
  description = "EKS cluster to associate with."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the service account."
  type        = string
  default     = "cloudcart"
}

variable "service_account_name" {
  description = "Kubernetes service account name that pods use."
  type        = string
  default     = "cloudcart-dynamodb"
}

variable "role_name" {
  description = "Name of the IAM role to create."
  type        = string
  default     = "cloudcart-dynamodb-role"
}

variable "dynamodb_table_arns" {
  description = "Table ARNs the pods may access."
  type        = list(string)
}

variable "dynamodb_actions" {
  description = "DynamoDB actions to allow on the tables."
  type        = list(string)
  default = [
    "dynamodb:GetItem",
    "dynamodb:PutItem",
    "dynamodb:UpdateItem",
    "dynamodb:Scan",
    "dynamodb:Query",
    "dynamodb:BatchGetItem",
    "dynamodb:BatchWriteItem",
  ]
}

variable "common_tags" {
  description = "Tags applied to created resources."
  type        = map(string)
  default     = {}
}
