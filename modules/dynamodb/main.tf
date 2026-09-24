# =============================================================================
# DynamoDB module — flexible / dynamic
#
# Creates any number of tables from a single map variable. Each table supports:
#   - partition key (+ optional sort key)
#   - PAY_PER_REQUEST or PROVISIONED billing
#   - Global & Local Secondary Indexes
#   - TTL, Point-in-Time Recovery, Streams
#   - KMS encryption (shared key for all tables)
#   - optional cross-account resource policy
#
# You add/change tables ONLY in tfvars — nothing in this file changes.
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  # For each table, collect every attribute that is used as a key anywhere
  # (partition key, sort key, and any GSI hash/range keys). DynamoDB requires
  # an attribute definition for each key attribute.
  table_key_attributes = {
    for table_key, table_config in var.dynamodb_tables : table_key => distinct(compact(concat(
      [table_config.partition_key],
      table_config.enable_sort_key ? [table_config.sort_key] : [],
      flatten([for g in table_config.global_secondary_indexes : [
        g.hash_key,
        g.range_key != null ? g.range_key : ""
      ]])
    )))
  }

  # Accept either a bare KMS key id or a full ARN; build the ARN if only an id
  # was given. One key encrypts all tables.
  kms_key_arn = var.kms_key_id != null && var.kms_key_id != "" && !can(regex("^arn:aws:kms:", var.kms_key_id)) ? "arn:aws:kms:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:key/${var.kms_key_id}" : var.kms_key_id
}

# DynamoDB Tables
resource "aws_dynamodb_table" "tables" {
  for_each = var.dynamodb_tables

  name         = each.value.table_name
  billing_mode = each.value.billing_mode
  table_class  = each.value.table_class

  hash_key  = each.value.partition_key
  range_key = each.value.enable_sort_key ? each.value.sort_key : null

  deletion_protection_enabled = each.value.enable_deletion_protection

  # Provisioned throughput only applies to PROVISIONED billing mode.
  read_capacity  = each.value.billing_mode == "PROVISIONED" ? each.value.read_capacity : null
  write_capacity = each.value.billing_mode == "PROVISIONED" ? each.value.write_capacity : null

  # Declare each key attribute (default type String, override via attribute_types).
  dynamic "attribute" {
    for_each = toset(local.table_key_attributes[each.key])
    content {
      name = attribute.value
      type = lookup(each.value.attribute_types, attribute.value, "S")
    }
  }

  # Global Secondary Indexes.
  # The provider deprecated the inline hash_key/range_key arguments in favour of
  # nested key_schema blocks. We keep the simple hash_key/range_key inputs in
  # tfvars and translate them into key_schema here, so callers never write the
  # verbose form and no deprecation warnings are emitted.
  dynamic "global_secondary_index" {
    for_each = each.value.global_secondary_indexes
    content {
      name               = global_secondary_index.value.name
      projection_type    = global_secondary_index.value.projection_type
      non_key_attributes = global_secondary_index.value.projection_type == "INCLUDE" ? global_secondary_index.value.non_key_attributes : null

      read_capacity  = each.value.billing_mode == "PROVISIONED" ? global_secondary_index.value.read_capacity : null
      write_capacity = each.value.billing_mode == "PROVISIONED" ? global_secondary_index.value.write_capacity : null

      # HASH key (always present)
      key_schema {
        attribute_name = global_secondary_index.value.hash_key
        key_type       = "HASH"
      }
      # RANGE key (only when a range_key was provided)
      dynamic "key_schema" {
        for_each = global_secondary_index.value.range_key != null ? [global_secondary_index.value.range_key] : []
        content {
          attribute_name = key_schema.value
          key_type       = "RANGE"
        }
      }
    }
  }

  # Local Secondary Indexes
  dynamic "local_secondary_index" {
    for_each = each.value.local_secondary_indexes
    content {
      name               = local_secondary_index.value.name
      range_key          = local_secondary_index.value.range_key
      projection_type    = local_secondary_index.value.projection_type
      non_key_attributes = local_secondary_index.value.projection_type == "INCLUDE" ? local_secondary_index.value.non_key_attributes : null
    }
  }

  # Encryption at rest with a customer-managed KMS key (same key for all tables).
  server_side_encryption {
    enabled     = true
    kms_key_arn = local.kms_key_arn
  }

  # TTL (optional)
  dynamic "ttl" {
    for_each = each.value.enable_ttl ? [1] : []
    content {
      attribute_name = each.value.ttl_attribute_name
      enabled        = true
    }
  }

  # Point-in-Time Recovery (optional)
  dynamic "point_in_time_recovery" {
    for_each = each.value.enable_pitr ? [1] : []
    content {
      enabled = true
    }
  }

  # DynamoDB Streams (optional)
  stream_enabled   = each.value.enable_streams
  stream_view_type = each.value.enable_streams ? each.value.stream_view_type : null

  tags = merge(
    var.common_tags,
    each.value.tags,
    {
      Name = each.value.table_name
    }
  )
}

# Optional resource-based policy for cross-account access.
data "aws_iam_policy_document" "dynamodb_resource_policy" {
  for_each = {
    for k, v in var.dynamodb_tables : k => v
    if length(v.resource_policy_principals) > 0
  }

  statement {
    sid    = "CrossAccountAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = each.value.resource_policy_principals
    }

    actions   = each.value.resource_policy_actions
    resources = [aws_dynamodb_table.tables[each.key].arn]
  }
}

resource "aws_dynamodb_resource_policy" "this" {
  for_each = {
    for k, v in var.dynamodb_tables : k => v
    if length(v.resource_policy_principals) > 0
  }

  resource_arn = aws_dynamodb_table.tables[each.key].arn
  policy       = data.aws_iam_policy_document.dynamodb_resource_policy[each.key].json
}
