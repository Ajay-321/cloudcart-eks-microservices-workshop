#!/usr/bin/env bash
# ===========================================================================
# create-dynamodb-tables.sh
#
# Creates the 6 DynamoDB tables CloudCart uses when USE_DYNAMODB=true, and
# ALSO creates the IAM policy CloudCartDynamoDBPolicy scoped to those tables.
# Billing mode PAY_PER_REQUEST = no capacity planning, pay only for usage.
# Idempotent: skips tables and the policy that already exist.
#
# Creating the IAM policy here prevents the common
# `eksctl create podidentityassociation` failure where the policy ARN
# doesn't exist yet.
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

# ---------------------------------------------------------------------------
# IAM policy: CloudCartDynamoDBPolicy
#
# Scoped to only the 6 CloudCart tables in this region/account, with the
# actions the app uses. Created idempotently so the pod-identity association
# (eksctl create podidentityassociation) has a policy ARN to attach.
# ---------------------------------------------------------------------------
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
POLICY_NAME="CloudCartDynamoDBPolicy"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

# Build the policy document into a temp file, cleaned up on exit.
POLICY_FILE="$(mktemp)"
trap 'rm -f "$POLICY_FILE"' EXIT

cat > "$POLICY_FILE" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CloudCartDynamoDBAccess",
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
        "dynamodb:Scan",
        "dynamodb:BatchGetItem",
        "dynamodb:BatchWriteItem",
        "dynamodb:DescribeTable"
      ],
      "Resource": [
        "arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/cloudcart-products",
        "arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/cloudcart-inventory",
        "arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/cloudcart-carts",
        "arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/cloudcart-orders",
        "arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/cloudcart-payments",
        "arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/cloudcart-users"
      ]
    }
  ]
}
EOF

# Idempotent create: get-policy is guarded so its non-zero exit is safe under set -e.
if aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  echo "IAM policy exists: $POLICY_NAME"
else
  aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document file://"$POLICY_FILE" >/dev/null
  echo "Created IAM policy: $POLICY_NAME"
fi

echo "Policy ARN: $POLICY_ARN"
echo "Next: associate it via eksctl create podidentityassociation (see README Step 5)."
