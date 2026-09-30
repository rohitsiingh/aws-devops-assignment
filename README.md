# AWS DevOps Assignment

Solutions to the 5-part Terraform/IAM assignment. Each task lives in its own
folder as an independent Terraform root module so it can be reviewed/applied
in isolation. Full written answers to every "explain in NOTES.md" prompt are
in [NOTES.md](./NOTES.md).

## Layout

```
task1-ec2-provisioning/   Task 1 - single-variable, 5-instance EC2 module
task2-remote-state/       Task 2 - S3 backend added to Task 1 + bootstrap stack
task3-iam-cross-account/  Task 3 - Account A groups/roles + Account B roleC
task4-least-privilege-policy/  Task 4 - ci IAM policy JSON
task5-bugfix/             Task 5 - before/ (broken) and after/ (fixed)
NOTES.md                  Written answers for all 5 tasks
```

## Task 1 - Multi-Instance EC2 Provisioning

`task1-ec2-provisioning/` - all 5 instances are driven by one map variable,
`var.instances` (see `variables.tf` and `terraform.tfvars.example`). The
`database` instance uses `io2` storage and is the one instance guarded by
`lifecycle.prevent_destroy` (see NOTES.md for why, and why that required
splitting into two `for_each` resource blocks instead of one).

```
cd task1-ec2-provisioning
cp terraform.tfvars.example terraform.tfvars   # fill in real subnet/SG/key values
terraform init
terraform plan
```

## Task 2 - Remote State & Locking

`task1-ec2-provisioning/backend.tf` configures the S3 + DynamoDB backend.
`task2-remote-state/bootstrap/` is a separate, one-time-applied stack that
creates the S3 bucket and DynamoDB lock table themselves (a backend can't
create the bucket it's about to store its own state in).

```
cd task2-remote-state/bootstrap
terraform init
terraform apply   # run once, before task1's `terraform init` picks up backend.tf
```

## Task 3 - Multi-Account IAM & Cross-Account Access

`task3-iam-cross-account/` - `account-a.tf` (group1, group2, roleA, roleB)
and `account-b.tf` (roleC). Uses two aliased `aws` providers since the config
spans two accounts; point `account_a_profile` / `account_b_profile` at real
CLI profiles for each account before applying.

## Task 4 - Least-Privilege Policy Writing

`task4-least-privilege-policy/ci-policy.json` - the custom policy for the
`ci` user. `attach-example.tf` shows how it attaches to the `ci` user from
Task 3.

## Task 5 - Find and Fix the Bug

`task5-bugfix/before/` is the assignment's broken snippet (kept for
reference, not meant to be applied). `task5-bugfix/after/` is the fix.
