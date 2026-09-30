# Remote state backend for this module (Task 2).
#
# The S3 bucket and DynamoDB table referenced here are NOT created by this
# module - they are bootstrapped once, out-of-band, by
# task2-remote-state/bootstrap (a state backend can't reliably create the
# bucket it is about to store its own state in). See task2-remote-state/
# for that bootstrap config and NOTES.md for the locking explanation.
#
# Backend blocks cannot use variables/interpolation, so update the
# placeholder values below (or pass them via `terraform init -backend-config=`)
# to match whatever the bootstrap step actually created.
terraform {
  backend "s3" {
    bucket         = "acme-terraform-state-aws-devops-assignment"
    key            = "task1-ec2-provisioning/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
