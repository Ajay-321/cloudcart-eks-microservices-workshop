# =============================================================================
# EKS module — IAM roles
#
# Two roles are always needed:
#   1. Cluster role  -> assumed by the EKS control plane
#   2. Node role     -> assumed by worker nodes / Auto Mode instances
#
# The set of managed policies on the node role differs slightly:
#   - Auto Mode needs the AmazonEKSWorkerNodeMinimalPolicy + ECR pull-only.
#   - Classic node groups need the full worker node + CNI + ECR read policies.
# We attach the right set based on var.enable_auto_mode.
# =============================================================================

data "aws_partition" "current" {}

# ---- Cluster role ----------------------------------------------------------
data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
  tags               = var.common_tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Auto Mode requires the cluster role to also manage compute/LB/storage.
resource "aws_iam_role_policy_attachment" "cluster_compute" {
  count      = var.enable_auto_mode ? 1 : 0
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSComputePolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_block_storage" {
  count      = var.enable_auto_mode ? 1 : 0
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSBlockStoragePolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_lb" {
  count      = var.enable_auto_mode ? 1 : 0
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSLoadBalancingPolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_networking" {
  count      = var.enable_auto_mode ? 1 : 0
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSNetworkingPolicy"
}

# ---- Node role -------------------------------------------------------------
data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = var.common_tags
}

# Policies common to both modes: pull images from ECR.
resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# --- Classic managed node group policies (auto mode OFF) ---
resource "aws_iam_role_policy_attachment" "node_worker" {
  count      = var.enable_auto_mode ? 0 : 1
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  count      = var.enable_auto_mode ? 0 : 1
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# --- Auto Mode node policy (auto mode ON) ---
resource "aws_iam_role_policy_attachment" "node_auto_minimal" {
  count      = var.enable_auto_mode ? 1 : 0
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy"
}
