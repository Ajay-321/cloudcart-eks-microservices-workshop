# =============================================================================
# Environment variables. Defaults are sensible for a dev cluster; override any
# of them in terraform.tfvars.
# =============================================================================

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev/demo/prod)."
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "cloudcart"
}

variable "kubernetes_version" {
  description = "Kubernetes version."
  type        = string
  default     = "1.31"
}

# ---- Networking ------------------------------------------------------------
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  description = "AZs to use. Empty = auto-pick two in the region."
  type        = list(string)
  default     = []
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.0.0/20", "10.0.16.0/20"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.32.0/20", "10.0.48.0/20"]
}

variable "enable_nat_gateway" {
  type    = bool
  default = true
}

variable "single_nat_gateway" {
  type    = bool
  default = true
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS public API endpoint."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "access_entries" {
  description = "Extra IAM principals to grant cluster access (see modules/eks/variables.tf). Empty = only the cluster creator is admin."
  type = map(object({
    principal_arn = string
    policy_arn    = string
    access_scope  = optional(string, "cluster")
    namespaces    = optional(list(string), [])
    type          = optional(string, "STANDARD")
  }))
  default = {}
}

# ---- Auto Mode switch ------------------------------------------------------
variable "enable_auto_mode" {
  description = "true = EKS Auto Mode; false = classic managed node group."
  type        = bool
  default     = false
}

variable "auto_mode_node_pools" {
  type    = list(string)
  default = ["general-purpose", "system"]
}

# ---- Managed node group sizing (classic mode) ------------------------------
variable "instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "capacity_type" {
  type    = string
  default = "ON_DEMAND"
}

variable "desired_size" {
  type    = number
  default = 2
}

variable "min_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 3
}

variable "disk_size" {
  type    = number
  default = 30
}

# ---- ECR -------------------------------------------------------------------
variable "ecr_repositories" {
  description = "ECR repos to create (one per image)."
  type        = list(string)
  default = [
    "cloudcart-frontend",
    "cloudcart-product-service",
    "cloudcart-inventory-service",
    "cloudcart-cart-service",
    "cloudcart-order-service",
    "cloudcart-payment-service",
  ]
}

# ---- DynamoDB + Pod Identity ----------------------------------------------
variable "enable_dynamodb" {
  description = "Create DynamoDB tables + Pod Identity role for the AWS data phase."
  type        = bool
  default     = true
}

variable "dynamodb_tables" {
  description = "Map of DynamoDB tables to create. Passed straight to the dynamodb module (see its variables.tf for every supported field)."
  type = map(object({
    table_name    = string
    partition_key = string

    enable_sort_key = optional(bool, false)
    sort_key        = optional(string)

    billing_mode   = optional(string, "PAY_PER_REQUEST")
    read_capacity  = optional(number, 5)
    write_capacity = optional(number, 5)

    table_class                = optional(string, "STANDARD")
    enable_deletion_protection = optional(bool, true)
    attribute_types            = optional(map(string), {})

    global_secondary_indexes = optional(list(object({
      name               = string
      hash_key           = string
      range_key          = optional(string)
      projection_type    = string
      non_key_attributes = optional(list(string))
      read_capacity      = optional(number, 5)
      write_capacity     = optional(number, 5)
    })), [])

    local_secondary_indexes = optional(list(object({
      name               = string
      range_key          = string
      projection_type    = string
      non_key_attributes = optional(list(string))
    })), [])

    enable_ttl         = optional(bool, false)
    ttl_attribute_name = optional(string, "ttl")
    enable_pitr        = optional(bool, true)
    enable_streams     = optional(bool, false)
    stream_view_type   = optional(string, "NEW_AND_OLD_IMAGES")

    resource_policy_principals = optional(list(string), [])
    resource_policy_actions    = optional(list(string), [])

    tags = optional(map(string), {})
  }))
  default = {}
}

variable "k8s_namespace" {
  type    = string
  default = "cloudcart"
}

variable "k8s_service_account" {
  type    = string
  default = "cloudcart-dynamodb"
}

variable "common_tags" {
  description = "Tags applied to every resource. Set this in terraform.tfvars."
  type        = map(string)
  default     = {}
}
