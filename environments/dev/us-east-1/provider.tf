terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.70"
    }
  }
}

provider "aws" {
  region = var.region

  # Every resource gets these tags automatically.
  default_tags {
    tags = {
      Project     = "cloudcart"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
