# =============================================================================
# EKS module — cluster, addons, and (classic mode) managed node group
# =============================================================================

# ---- The EKS cluster (control plane) ---------------------------------------
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
  }

  # ---- Auto Mode block ----
  # Only "enabled" when enable_auto_mode = true. In classic mode we still emit
  # the block with enabled=false and no node pools (AWS treats this as off).
  compute_config {
    enabled       = var.enable_auto_mode
    node_pools    = var.enable_auto_mode ? var.auto_mode_node_pools : []
    node_role_arn = var.enable_auto_mode ? aws_iam_role.node.arn : null
  }

  # Auto Mode also manages load balancing + block storage; enabling these
  # alongside compute is required for a functional Auto Mode cluster.
  kubernetes_network_config {
    elastic_load_balancing {
      enabled = var.enable_auto_mode
    }
  }

  storage_config {
    block_storage {
      enabled = var.enable_auto_mode
    }
  }

  # Bootstrap the creator (the Terraform identity) as a cluster admin so you
  # can immediately run kubectl after `terraform apply`.
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = merge(var.common_tags, { Name = var.cluster_name })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_compute,
    aws_iam_role_policy_attachment.cluster_block_storage,
    aws_iam_role_policy_attachment.cluster_lb,
    aws_iam_role_policy_attachment.cluster_networking,
  ]
}

# ---- Addons (classic mode only) --------------------------------------------
# Auto Mode bundles networking/storage, so we skip standalone addons there.
resource "aws_eks_addon" "this" {
  for_each = var.enable_auto_mode ? {} : { for a in var.addons : a.name => a }

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value.name
  addon_version               = try(each.value.version, null)
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.common_tags

  # Node group must exist before CNI/coredns land on it.
  depends_on = [aws_eks_node_group.this]
}

# ---- Extra cluster access entries (optional, from tfvars) ------------------
# One access entry per principal, plus the policy association that grants it
# permissions. The cluster creator is admin automatically and does NOT need an
# entry here.
resource "aws_eks_access_entry" "this" {
  for_each = var.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  type          = each.value.type
  tags          = var.common_tags
}

resource "aws_eks_access_policy_association" "this" {
  for_each = var.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = each.value.access_scope
    namespaces = each.value.access_scope == "namespace" ? each.value.namespaces : null
  }

  depends_on = [aws_eks_access_entry.this]
}

# ---- Managed node group (classic mode only) --------------------------------
resource "aws_eks_node_group" "this" {
  count = var.enable_auto_mode ? 0 : 1

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = var.node_group_name
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  instance_types = var.instance_types
  capacity_type  = var.capacity_type
  disk_size      = var.disk_size

  # Node group size — the three values tuned in tfvars.
  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = { app = "cloudcart" }
  tags   = var.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]

  # Let Kubernetes autoscaler change desired_size without Terraform reverting it.
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}
