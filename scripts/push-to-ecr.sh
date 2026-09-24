#!/usr/bin/env bash
# ===========================================================================
# push-to-ecr.sh
#
# Builds each CloudCart image and pushes it to Amazon ECR (Elastic Container
# Registry). Run this AFTER you can build locally and BEFORE deploying to EKS.
#
# What it does per service:
#   1. Ensure an ECR repository named cloudcart-<service> exists (create if not)
#   2. docker build the image
#   3. Tag it for the ECR registry
#   4. docker push it
#
# Prereqs: AWS CLI logged in (aws configure / SSO) and Docker running.
# Usage:   AWS_REGION=us-east-1 ./scripts/push-to-ecr.sh
# ===========================================================================
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
# Discover the current AWS account id from your credentials
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
TAG="${IMAGE_TAG:-1.0}"

# Log Docker in to your private ECR registry (token valid ~12h)
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

# "build-directory:repo-suffix" pairs
for item in \
  "frontend:frontend" \
  "services/product-service:product-service" \
  "services/inventory-service:inventory-service" \
  "services/cart-service:cart-service" \
  "services/order-service:order-service" \
  "services/payment-service:payment-service" \
  "services/auth-service:auth-service"
do
  DIR="${item%%:*}"
  REPO="${item##*:}"

  # Create the repository once; ignore error if it already exists
  aws ecr describe-repositories --repository-names "cloudcart-${REPO}" --region "$REGION" >/dev/null 2>&1 \
    || aws ecr create-repository --repository-name "cloudcart-${REPO}" --region "$REGION" >/dev/null

  docker build -t "cloudcart-${REPO}:${TAG}" "./${DIR}"
  docker tag  "cloudcart-${REPO}:${TAG}" "${REGISTRY}/cloudcart-${REPO}:${TAG}"
  docker push "${REGISTRY}/cloudcart-${REPO}:${TAG}"
done

echo "Images pushed to ${REGISTRY} (tag ${TAG})"
