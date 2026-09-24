# =============================================================================
# EKS Pod Identity module
#
# Creates an IAM role that a Kubernetes ServiceAccount can assume, and wires it
# to the cluster with an EKS Pod Identity association. Pods using that service
# account then get temporary AWS credentials automatically — no access keys in
# Kubernetes Secrets.
#
# Here it grants least-privilege DynamoDB access limited to the CloudCart tables.
# =============================================================================

# Trust policy: the EKS Pod Identity service assumes this role on behalf of pods.
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.common_tags
}

# Least-privilege: only the DynamoDB actions the services call, only on the
# CloudCart tables passed in.
data "aws_iam_policy_document" "dynamodb" {
  statement {
    effect    = "Allow"
    actions   = var.dynamodb_actions
    resources = var.dynamodb_table_arns
  }

  dynamic "statement" {
    for_each = var.kms_key_arn != "" ? [var.kms_key_arn] : []
    content {
      sid    = "DynamoDBKMSAccess"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey",
      ]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_policy" "dynamodb" {
  name   = "${var.role_name}-dynamodb"
  policy = data.aws_iam_policy_document.dynamodb.json
  tags   = var.common_tags
}

resource "aws_iam_role_policy_attachment" "dynamodb" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.dynamodb.arn
}

# The association binding: (cluster, namespace, service account) -> IAM role.
resource "aws_eks_pod_identity_association" "this" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account_name
  role_arn        = aws_iam_role.this.arn
  tags            = var.common_tags
}
