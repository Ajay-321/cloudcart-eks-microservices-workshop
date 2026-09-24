# =============================================================================
# Environment: dev / us-east-1
#
# Root module that wires the reusable modules together. Nothing here needs
# editing per environment — all tunables (region, sizes, instance types, auto
# mode, tables, tags) live in terraform.tfvars.
# =============================================================================

locals {
  # Derive AZ names from the region (e.g. us-east-1a/b) unless overridden.
  azs = length(var.azs) > 0 ? var.azs : [for z in ["a", "b"] : "${var.region}${z}"]
}

# ---- Networking ------------------------------------------------------------
module "vpc" {
  source = "../../../modules/vpc"

  name                 = var.cluster_name
  vpc_cidr             = var.vpc_cidr
  azs                  = local.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway
}

# ---- EKS cluster (+ node group when auto mode is OFF) ----------------------
module "eks" {
  source = "../../../modules/eks"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.vpc.vpc_id
  # Nodes/control-plane ENIs go in private subnets; public subnets host the LBs.
  subnet_ids          = module.vpc.private_subnet_ids
  public_access_cidrs = var.public_access_cidrs

  # Grant extra IAM users/roles kubectl access (empty by default).
  access_entries = var.access_entries

  # ---- THE switch ----
  enable_auto_mode     = var.enable_auto_mode
  auto_mode_node_pools = var.auto_mode_node_pools

  # ---- Classic managed node group knobs (ignored in auto mode) ----
  instance_types = var.instance_types
  capacity_type  = var.capacity_type
  desired_size   = var.desired_size
  min_size       = var.min_size
  max_size       = var.max_size
  disk_size      = var.disk_size

  common_tags = var.common_tags
}

# ---- Container registries (one repo per image) -----------------------------
module "ecr" {
  source           = "../../../modules/ecr"
  repository_names = var.ecr_repositories
  common_tags      = var.common_tags
}

# ---- KMS key used to encrypt the DynamoDB tables ---------------------------
module "kms" {
  source = "../../../modules/kms"
  count  = var.enable_dynamodb ? 1 : 0

  alias_name  = var.cluster_name
  common_tags = var.common_tags
}

# ---- DynamoDB tables (only when the app runs in DynamoDB mode) -------------
module "dynamodb" {
  source = "../../../modules/dynamodb"
  count  = var.enable_dynamodb ? 1 : 0

  dynamodb_tables = var.dynamodb_tables
  kms_key_id      = module.kms[0].key_id
  common_tags     = var.common_tags
}

# ---- Pod Identity: bind the cloudcart-dynamodb SA to a scoped IAM role ------
module "pod_identity" {
  source = "../../../modules/eks-pod-identity"
  count  = var.enable_dynamodb ? 1 : 0

  cluster_name         = module.eks.cluster_name
  namespace            = var.k8s_namespace
  service_account_name = var.k8s_service_account
  dynamodb_table_arns  = module.dynamodb[0].table_arns_list
  common_tags          = var.common_tags

  # Cluster must exist before we can create a Pod Identity association on it.
  # (Implied by cluster_name above; stated explicitly for clarity.)
  depends_on = [module.eks, module.dynamodb]
}
