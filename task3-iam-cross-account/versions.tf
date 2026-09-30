terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Two aliased providers because this config spans two AWS accounts.
# In practice these would use separate named CLI profiles / assumed-role
# credentials for Account A (000000000000) and Account B (111111111111).
provider "aws" {
  alias   = "account_a"
  region  = var.aws_region
  profile = var.account_a_profile
}

provider "aws" {
  alias   = "account_b"
  region  = var.aws_region
  profile = var.account_b_profile
}
