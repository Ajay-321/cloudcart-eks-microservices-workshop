# =============================================================================
# DynamoDB module — inputs
# =============================================================================

variable "dynamodb_tables" {
  description = "Map of DynamoDB tables to create with their configurations."
  type = map(object({
    table_name    = string
    partition_key = string

    # Sort key configuration
    enable_sort_key = optional(bool, false)
    sort_key        = optional(string)

    # Billing configuration
    billing_mode   = optional(string, "PAY_PER_REQUEST")
    read_capacity  = optional(number, 5) # Only used for PROVISIONED mode
    write_capacity = optional(number, 5) # Only used for PROVISIONED mode

    # Table class
    table_class = optional(string, "STANDARD")

    # Deletion protection
    enable_deletion_protection = optional(bool, true)

    # Attribute types for all key attributes (including GSI/LSI keys).
    # Default "S" (String); use "N" (Number) or "B" (Binary) as needed.
    attribute_types = optional(map(string), {})

    # Global Secondary Indexes
    global_secondary_indexes = optional(list(object({
      name               = string
      hash_key           = string
      range_key          = optional(string)
      projection_type    = string
      non_key_attributes = optional(list(string))
      read_capacity      = optional(number, 5) # Only used for PROVISIONED mode
      write_capacity     = optional(number, 5) # Only used for PROVISIONED mode
    })), [])

    # Local Secondary Indexes
    local_secondary_indexes = optional(list(object({
      name               = string
      range_key          = string
      projection_type    = string
      non_key_attributes = optional(list(string))
    })), [])

    # TTL configuration
    enable_ttl         = optional(bool, false)
    ttl_attribute_name = optional(string, "ttl")

    # Point-in-Time Recovery
    enable_pitr = optional(bool, true)

    # DynamoDB Streams
    enable_streams   = optional(bool, false)
    stream_view_type = optional(string, "NEW_AND_OLD_IMAGES")

    # Resource policy for cross-account access
    resource_policy_principals = optional(list(string), [])
    resource_policy_actions = optional(list(string), [
      "dynamodb:Get*",
      "dynamodb:List*",
      "dynamodb:Put*",
      "dynamodb:Update*",
      "dynamodb:Describe*",
      "dynamodb:Scan",
      "dynamodb:Query",
      "dynamodb:DeleteItem"
    ])

    # Table-specific tags
    tags = optional(map(string), {})
  }))

  default = {}

  validation {
    condition = alltrue([
      for k, v in var.dynamodb_tables :
      contains(["STANDARD", "STANDARD_INFREQUENT_ACCESS"], v.table_class)
    ])
    error_message = "Table class must be either STANDARD or STANDARD_INFREQUENT_ACCESS."
  }

  validation {
    condition = alltrue([
      for k, v in var.dynamodb_tables :
      contains(["PAY_PER_REQUEST", "PROVISIONED"], v.billing_mode)
    ])
    error_message = "Billing mode must be either PAY_PER_REQUEST or PROVISIONED."
  }

  validation {
    condition = alltrue([
      for k, v in var.dynamodb_tables :
      !v.enable_sort_key || v.sort_key != null
    ])
    error_message = "sort_key must be provided when enable_sort_key is true."
  }

  validation {
    condition = alltrue([
      for k, v in var.dynamodb_tables :
      !v.enable_streams || contains(["KEYS_ONLY", "NEW_IMAGE", "OLD_IMAGE", "NEW_AND_OLD_IMAGES"], v.stream_view_type)
    ])
    error_message = "stream_view_type must be one of: KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES."
  }
}

variable "kms_key_id" {
  description = "KMS Key ID (or ARN) used to encrypt all DynamoDB tables."
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all DynamoDB tables."
  type        = map(string)
  default     = {}
}
