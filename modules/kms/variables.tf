# =============================================================================
# KMS module — inputs
# =============================================================================

variable "alias_name" {
  description = "Alias for the KMS key (without the 'alias/' prefix)."
  type        = string
  default     = "cloudcart"
}

variable "description" {
  description = "Description shown in the KMS console."
  type        = string
  default     = "CloudCart customer-managed key"
}

variable "deletion_window_in_days" {
  description = "Waiting period (days) before the key is deleted (7-30)."
  type        = number
  default     = 7
}

variable "enable_key_rotation" {
  description = "Automatically rotate the key material yearly."
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Tags applied to the key."
  type        = map(string)
  default     = {}
}
