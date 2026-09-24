terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.70" # 5.70+ supports EKS Auto Mode (compute_config)
    }
  }
}
