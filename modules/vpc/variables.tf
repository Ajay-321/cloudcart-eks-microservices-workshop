# =============================================================================
# VPC module — inputs
# A dedicated VPC with public + private subnets across N availability zones.
# EKS needs specific subnet tags so the AWS load balancer controller can find
# subnets for public (internet-facing) and internal load balancers.
# =============================================================================

variable "name" {
  description = "Name prefix for all VPC resources (usually the cluster name)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC, e.g. 10.0.0.0/16."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "List of Availability Zones to spread subnets across."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ). Must match length of azs."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ). Must match length of azs."
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Create a NAT gateway so private-subnet nodes can reach the internet (pull images, call AWS APIs)."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use ONE NAT gateway for all AZs (lower cost) instead of one per AZ (higher availability)."
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Extra tags applied to every resource."
  type        = map(string)
  default     = {}
}
