# One-time bootstrap for the Terraform remote state backend used by
# task1-ec2-provisioning (and any other module in this repo).
#
# This has its own local state (or is applied once by hand) precisely
# because it creates the bucket/table that everything else's remote
# state depends on - it cannot depend on itself.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "state_bucket_name" {
  type    = string
  default = "acme-terraform-state-aws-devops-assignment"
}

variable "lock_table_name" {
  type    = string
  default = "terraform-state-lock"
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name

  # Guard against `terraform destroy` accidentally deleting the bucket that
  # holds every other module's state.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name      = var.state_bucket_name
    Purpose   = "terraform-remote-state"
    ManagedBy = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_lock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name      = var.lock_table_name
    Purpose   = "terraform-state-locking"
    ManagedBy = "terraform"
  }
}

output "state_bucket_name" {
  value = aws_s3_bucket.terraform_state.id
}

output "lock_table_name" {
  value = aws_dynamodb_table.terraform_lock.name
}
