#!/usr/bin/env bash
# ===========================================================================
# create-dynamodb-tables.sh
#
# Creates the 6 DynamoDB tables CloudCart uses when USE_DYNAMODB=true.
# Billing mode PAY_PER_REQUEST = no capacity planning, pay only for usage.
# Idempotent: skips tables that already exist.
#
# IMPORTANT: these table names must match the DYNAMODB_TABLE env values in
# k8s/aws/*-deployment.yaml.
#
# Usage: AWS_REGION=us-east-1 ./scripts/create-dynamodb-tables.sh
# ===========================================================================
set -euo pipefail
REGION="${AWS_REGION:-us-east-1}"

create_table () {
  NAME="$1"; KEY="$2"   # table name + partition (HASH) key attribute
  if aws dynamodb describe-table --table-name "$NAME" --region "$REGION" >/dev/null 2>&1; then
    echo "Table exists: $NAME"
  else
    aws dynamodb create-table \
      --table-name "$NAME" \
      --attribute-definitions AttributeName="$KEY",AttributeType=S \
      --key-schema AttributeName="$KEY",KeyType=HASH \
      --billing-mode PAY_PER_REQUEST \
      --region "$REGION" >/dev/null
    echo "Created: $NAME"
  fi
}

# table name           partition key
create_table cloudcart-products  id
create_table cloudcart-inventory productId
create_table cloudcart-carts     userId
create_table cloudcart-orders    orderId
create_table cloudcart-payments  paymentId
create_table cloudcart-users     email
