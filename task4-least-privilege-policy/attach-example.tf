# Illustrative wiring showing how ci-policy.json attaches to the `ci` user
# created in Task 3 (task3-iam-cross-account/account-a.tf). Kept in its own
# folder/state so Task 4 can be graded independently of Task 3; in a real
# repo this would likely just be another resource in account-a.tf instead.

variable "ci_user_name" {
  type    = string
  default = "ci"
}

resource "aws_iam_user_policy" "ci_least_privilege" {
  name   = "ci-pipeline-least-privilege"
  user   = var.ci_user_name
  policy = file("${path.module}/ci-policy.json")
}
