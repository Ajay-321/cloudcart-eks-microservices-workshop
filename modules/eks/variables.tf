# =============================================================================
# EKS module — inputs
#
# This ONE module can build TWO shapes of cluster, controlled by enable_auto_mode:
#
#   enable_auto_mode = false  -> classic EKS + a managed node group you size with
#                                min/max/desired + instance_types (via tfvars).
#   enable_auto_mode = true   -> EKS Auto Mode: AWS manages the compute (nodes,
#                                scaling, patching). No node group is created.
#
# Everything else (name, version, networking) is shared.
# =============================================================================

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes control-plane version, e.g. 1.31."
  type        = string
  default     = "1.31"
}

variable "vpc_id" {
  description = "VPC the cluster runs in."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the EKS control plane ENIs and (classic mode) nodes. Usually private subnets."
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Allow reaching the API server from the internet (needed for kubectl from your laptop)."
  type        = bool
  default     = true
}

variable "endpoint_private_access" {
  description = "Allow reaching the API server privately from inside the VPC."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Lock this down in production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ---- Auto Mode switch ------------------------------------------------------
variable "enable_auto_mode" {
  description = "true = EKS Auto Mode (AWS-managed compute). false = classic managed node group."
  type        = bool
  default     = false
}

variable "auto_mode_node_pools" {
  description = "Built-in Auto Mode node pools to enable (only used when enable_auto_mode = true)."
  type        = list(string)
  default     = ["general-purpose", "system"]
}

# ---- Classic managed node group settings (only used when auto mode is off) --
variable "node_group_name" {
  description = "Name of the managed node group (classic mode)."
  type        = string
  default     = "cloudcart-workers"
}

variable "instance_types" {
  description = "EC2 instance types for the managed node group. Set via tfvars."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "capacity_type" {
  description = "ON_DEMAND or SPOT for the managed node group."
  type        = string
  default     = "ON_DEMAND"
}

variable "desired_size" {
  description = "Desired number of worker nodes. Set via tfvars."
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Minimum number of worker nodes. Set via tfvars."
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of worker nodes. Set via tfvars."
  type        = number
  default     = 3
}

variable "disk_size" {
  description = "EBS root volume size (GiB) per node."
  type        = number
  default     = 30
}

variable "addons" {
  description = "EKS addons to install (ignored in Auto Mode which bundles networking/storage)."
  type = list(object({
    name    = string
    version = optional(string)
  }))
  default = [
    { name = "vpc-cni" },
    { name = "coredns" },
    { name = "kube-proxy" },
    { name = "eks-pod-identity-agent" },
  ]
}

# ---- Extra cluster access (EKS access entries) -----------------------------
# The IAM identity that CREATES the cluster is admin automatically. To let
# ANOTHER IAM user/role run kubectl (e.g. a teammate, a CI role, or an EC2
# instance role), add an access entry here. Empty by default => nothing added.
variable "access_entries" {
  description = <<-EOT
    Map of extra IAM principals to grant cluster access, keyed by a label.
    Each entry associates an AWS access policy (by ARN) with an access scope.
    Example (grant an IAM user cluster-admin):
      {
        alice = {
          principal_arn = "arn:aws:iam::111122223333:user/alice"
          policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope  = "cluster"
        }
      }
  EOT
  type = map(object({
    principal_arn = string
    # Common policy ARNs:
    #   .../AmazonEKSClusterAdminPolicy  (full admin)
    #   .../AmazonEKSAdminPolicy         (admin within namespaces)
    #   .../AmazonEKSViewPolicy          (read-only)
    policy_arn = string
    # "cluster" (whole cluster) or "namespace" (limited to namespaces below)
    access_scope = optional(string, "cluster")
    namespaces   = optional(list(string), [])
    # STANDARD is the normal case; EC2_LINUX is for node/instance roles.
    type = optional(string, "STANDARD")
  }))
  default = {}
}

variable "common_tags" {
  description = "Tags applied to all EKS resources."
  type        = map(string)
  default     = {}
}
