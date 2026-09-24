# =============================================================================
# ECR module — inputs
# =============================================================================

variable "repository_names" {
  description = "List of ECR repository names to create (one per image)."
  type        = list(string)
}

variable "image_tag_mutability" {
  description = "MUTABLE (tags can be overwritten) or IMMUTABLE (tags are write-once, safer)."
  type        = string
  default     = "MUTABLE"
}

variable "scan_on_push" {
  description = "Run a vulnerability scan whenever an image is pushed."
  type        = bool
  default     = true
}

variable "force_delete" {
  description = "Allow deleting a repo that still contains images (handy for teardown)."
  type        = bool
  default     = true
}

variable "keep_last_images" {
  description = "How many recent images to retain per repository."
  type        = number
  default     = 10
}

variable "common_tags" {
  description = "Tags applied to every repository."
  type        = map(string)
  default     = {}
}
