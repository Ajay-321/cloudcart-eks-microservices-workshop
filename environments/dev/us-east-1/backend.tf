# =============================================================================
# Remote state backend (S3).
#
# Storing state remotely lets a team (and GitHub Actions) share one source of
# truth. Create the bucket ONCE before `terraform init`, e.g.:
#
#   aws s3 mb s3://cloudcart-tfstate-<youraccountid> --region us-east-1
#   aws s3api put-bucket-versioning --bucket cloudcart-tfstate-<youraccountid> \
#     --versioning-configuration Status=Enabled
#
# Then fill in the bucket name below (or pass -backend-config on init).
# For a first local experiment you can comment this whole block out to use
# local state.
#
# NOTE: values here cannot use variables; they must be literals.
# =============================================================================
terraform {
  backend "s3" {
    bucket       = "ajay-eks-demo-terraform-bucket"
    key          = "dev/us-east-1/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # S3 native state locking (no DynamoDB table needed)
  }
}
