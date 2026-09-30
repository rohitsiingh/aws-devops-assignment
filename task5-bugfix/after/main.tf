# Fixed version. See NOTES.md (Task 5) for why each change was necessary.

variable "shared_bucket_name" {
  type    = string
  default = "acme-account-b-shared-bucket"
}

data "aws_iam_policy_document" "roleC_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "AWS"
      # Bug 1 fix: roleB is a ROLE, not a user - the ARN must point at
      # role/roleB, not user/roleB. As written, the identifier referred to
      # an IAM user that doesn't exist, so AWS rejects the trust policy
      # (and even if a user named roleB did exist, that's a different
      # principal than the intended roleB role).
      identifiers = ["arn:aws:iam::000000000000:role/roleB"]
    }
  }
}

resource "aws_iam_role" "roleC" {
  name               = "roleC"
  assume_role_policy = data.aws_iam_policy_document.roleC_trust.json
}

resource "aws_iam_role_policy" "roleC_s3" {
  name = "roleC-s3-access"
  role = aws_iam_role.roleC.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "s3:*"
      # Bug 2 fix: Resource = "*" granted full access to every S3 bucket
      # (and every object in every bucket) in Account B, not the one named
      # bucket the task calls for. Scope it to the specific bucket's ARN
      # and its objects.
      Resource = [
        "arn:aws:s3:::${var.shared_bucket_name}",
        "arn:aws:s3:::${var.shared_bucket_name}/*",
      ]
    }]
  })
}
