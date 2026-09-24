#!/usr/bin/env bash
# ===========================================================================
# render-aws-manifests.sh
#
# The k8s/aws/*-deployment.yaml files use placeholders <ACCOUNT_ID> and
# <REGION> in their image references. This script replaces them in-place with
# your real AWS account id and region so the manifests point at YOUR ECR images.
#
# Run it once after pushing images to ECR and before `kubectl apply -f k8s/aws/`.
#
# Usage: AWS_REGION=us-east-1 ./scripts/render-aws-manifests.sh
# ===========================================================================
set -euo pipefail
REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

for f in k8s/aws/*-deployment.yaml; do
  # -i.bak works on both GNU and BSD/macOS sed; we delete the .bak after
  sed -i.bak \
    -e "s/<ACCOUNT_ID>/${ACCOUNT_ID}/g" \
    -e "s/<REGION>/${REGION}/g" "$f"
  rm -f "${f}.bak"
  echo "Rendered: $f"
done
