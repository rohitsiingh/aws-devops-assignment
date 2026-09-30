# ---------------------------------------------------------------------------
# Account B (111111111111)
# ---------------------------------------------------------------------------

# --- roleC: full access to ONE named bucket, assumable ONLY by roleB --------
#
# This trust policy is the key requirement: it names roleB's specific role
# ARN, not Account A's root. This is a genuine cross-account trust boundary,
# so - unlike roleA/roleB above - the trust policy itself is the ONLY gate.
# There is no Account-B-side IAM policy that further narrows things down, so
# if this trusted principals list included the account A root instead of
# roleB's ARN, EVERY identity in Account A that has (or later gets) an
# sts:AssumeRole allow would be able to assume roleC. See NOTES.md Q2 and
# task5-bugfix/ for the broken version of this exact mistake.
data "aws_iam_policy_document" "roleC_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_a_id}:role/roleB"]
    }
  }
}

resource "aws_iam_role" "roleC" {
  provider           = aws.account_b
  name               = "roleC"
  assume_role_policy = data.aws_iam_policy_document.roleC_trust.json
}

# Full access to the bucket - but scoped to that bucket's ARN and its
# objects, never Resource = "*". "Full access to a single named bucket"
# means full access to THAT bucket, not to every bucket in the account.
data "aws_iam_policy_document" "roleC_s3_access" {
  statement {
    effect  = "Allow"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${var.shared_bucket_name}",
      "arn:aws:s3:::${var.shared_bucket_name}/*",
    ]
  }
}

resource "aws_iam_role_policy" "roleC_s3_access" {
  provider = aws.account_b
  name     = "roleC-s3-full-access-single-bucket"
  role     = aws_iam_role.roleC.id
  policy   = data.aws_iam_policy_document.roleC_s3_access.json
}
