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
variable "kms_key_arn" {
  description = "ARN of the KMS key that encrypts the DynamoDB tables. When set, the role is granted kms:Decrypt/GenerateDataKey/DescribeKey on it so pods can read/write CMK-encrypted tables. Empty string = no KMS statement (AWS-owned key)."
  type        = string
  default     = ""
}
