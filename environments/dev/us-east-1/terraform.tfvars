# =============================================================================
# dev / us-east-1  —  the SINGLE control panel for this environment.
#
# Everything is set here. To adapt this to your own account, you typically
# change: region, cluster_name, vpc_cidr/subnets (if they clash with an
# existing VPC), and the ecr_repositories / dynamodb_tables names.
# You should never need to edit a .tf file.
# =============================================================================

# ---- Core -------------------------------------------------------------------
region             = "us-east-1"
environment        = "dev"
cluster_name       = "cloudcart" # used for the cluster, VPC name, KMS alias
kubernetes_version = "1.31"

# Tags applied to every resource.
common_tags = {
  Project     = "cloudcart"
  Environment = "dev"
  ManagedBy   = "terraform"
  Owner       = "platform"
}

# ---- Networking (2 AZs) -----------------------------------------------------
# If you already run a VPC on 10.0.0.0/16, change these to a free range
# (e.g. 10.20.0.0/16) so nothing overlaps.
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.0.0/20", "10.0.16.0/20"]
private_subnet_cidrs = ["10.0.32.0/20", "10.0.48.0/20"]
azs                  = [] # empty = auto-pick 2 AZs in the region, e.g. us-east-1a/b
enable_nat_gateway   = true
single_nat_gateway   = true # one NAT gateway to keep cost low (set false for HA)

# Who can reach the EKS public API endpoint. Lock down to your IP/CIDR in prod.
public_access_cidrs = ["0.0.0.0/0"]

# ---- Compute mode -----------------------------------------------------------
enable_auto_mode = false # false = managed node group (you size it below)
# When enable_auto_mode = true, AWS manages the nodes and the sizing below is
# ignored. Node pools used in that case:
auto_mode_node_pools = ["general-purpose", "system"]

# ---- Managed node group sizing (used when enable_auto_mode = false) ---------
instance_types = ["t3.medium"] # e.g. ["t3.large"] or ["t3.medium","t3a.medium"]
capacity_type  = "ON_DEMAND"   # or "SPOT" to save money
desired_size   = 0
min_size       = 0
max_size       = 3
disk_size      = 30

# ---- Extra cluster access (optional) ----------------------------------------
# The identity that runs `terraform apply` is cluster admin automatically.
# Add other IAM users/roles here to let them run kubectl (e.g. a CI role).
access_entries = {}
# access_entries = {
#   admin = {
#     principal_arn = "arn:aws:iam::689351349581:user/cloudcart-admin"
#     policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
#     access_scope  = "cluster"
#   }
# }

# ---- Container registries (one repo per image) ------------------------------
# Rename these to match your own registry naming if needed. Keep them in sync
# with the image references in k8s/aws/*-deployment.yaml and scripts/push-to-ecr.sh.
ecr_repositories = [
  "cloudcart-frontend",
  "cloudcart-product-service",
  "cloudcart-inventory-service",
  "cloudcart-cart-service",
  "cloudcart-order-service",
  "cloudcart-payment-service",
  "cloudcart-auth-service",
]

# ---- Data layer -------------------------------------------------------------
enable_dynamodb = true # create KMS key + DynamoDB tables + Pod Identity role

# Kubernetes namespace + service account the pods use for DynamoDB access.
k8s_namespace       = "cloudcart"
k8s_service_account = "cloudcart-dynamodb"

# The 6 CloudCart tables. table_name is the real AWS name and MUST match
# DYNAMODB_TABLE in k8s/aws/*-deployment.yaml. Add GSIs, TTL, PITR, streams, etc.
# per table — the dynamodb module supports them all.
dynamodb_tables = {
  products = {
    table_name    = "cloudcart-products"
    partition_key = "id"
    enable_pitr   = true
  }
  inventory = {
    table_name    = "cloudcart-inventory"
    partition_key = "productId"
  }
  carts = {
    table_name    = "cloudcart-carts"
    partition_key = "userId"
  }
  orders = {
    table_name    = "cloudcart-orders"
    partition_key = "orderId"
    # Example GSI to query a user's orders:
    global_secondary_indexes = [
      {
        name            = "byUser"
        hash_key        = "userId"
        projection_type = "ALL"
      }
    ]
    attribute_types = { userId = "S" }
  }
  payments = {
    table_name    = "cloudcart-payments"
    partition_key = "paymentId"
  }
  users = {
    table_name    = "cloudcart-users"
    partition_key = "email"
  }
}
