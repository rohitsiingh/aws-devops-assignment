# ---------------------------------------------------------------------------
# Account A (000000000000)
# ---------------------------------------------------------------------------

# --- group1: CLI/programmatic-only access -----------------------------------
# "CLI-only" is not an IAM permission - it's an access-METHOD constraint.
# It's enforced by (a) never creating an aws_iam_user_login_profile for these
# users, so they have no console password at all, and (b) an explicit Deny
# on any action performed via the console, as defense-in-depth in case a
# password is ever added out-of-band later.
resource "aws_iam_group" "group1" {
  provider = aws.account_a
  name     = "group1"
}

resource "aws_iam_user" "engine" {
  provider = aws.account_a
  name     = "engine"
  tags     = { Purpose = "automation" }
}

resource "aws_iam_user" "ci" {
  provider = aws.account_a
  name     = "ci"
  tags     = { Purpose = "automation" }
}

resource "aws_iam_group_membership" "group1_members" {
  provider = aws.account_a
  name     = "group1-membership"
  group    = aws_iam_group.group1.name
  users    = [aws_iam_user.engine.name, aws_iam_user.ci.name]
}

resource "aws_iam_access_key" "engine" {
  provider = aws.account_a
  user     = aws_iam_user.engine.name
}

resource "aws_iam_access_key" "ci" {
  provider = aws.account_a
  user     = aws_iam_user.ci.name
}

data "aws_iam_policy_document" "group1_deny_console" {
  statement {
    sid       = "DenyConsoleUsage"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]

    condition {
      test     = "Bool"
      variable = "aws:ViaAWSConsole"
      values   = ["true"]
    }
  }
}

resource "aws_iam_group_policy" "group1_deny_console" {
  provider = aws.account_a
  name     = "deny-console-access"
  group    = aws_iam_group.group1.name
  policy   = data.aws_iam_policy_document.group1_deny_console.json
}

# NOTE: group1's actual task permissions are intentionally not defined here.
# `ci`'s precise least-privilege permissions are defined in Task 4 and
# attached directly to the ci user there - see task4-least-privilege-policy/.

# --- group2: full console + CLI access --------------------------------------
resource "aws_iam_group" "group2" {
  provider = aws.account_a
  name     = "group2"
}

resource "aws_iam_user" "group2_users" {
  provider = aws.account_a
  for_each = toset(var.group2_users)
  name     = each.value
  tags     = { Purpose = "human-admin" }
}

resource "aws_iam_user_login_profile" "group2_users" {
  provider                = aws.account_a
  for_each                = aws_iam_user.group2_users
  user                    = each.value.name
  password_reset_required = true
}

resource "aws_iam_access_key" "group2_users" {
  provider = aws.account_a
  for_each = aws_iam_user.group2_users
  user     = each.value.name
}

resource "aws_iam_group_membership" "group2_members" {
  provider = aws.account_a
  name     = "group2-membership"
  group    = aws_iam_group.group2.name
  users    = [for u in aws_iam_user.group2_users : u.name]
}

resource "aws_iam_group_policy_attachment" "group2_admin" {
  provider   = aws.account_a
  group      = aws_iam_group.group2.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# --- roleA: administrative access to everything except IAM ------------------
data "aws_iam_policy_document" "roleA_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_a_id}:root"]
    }
  }
}

# Trusting the account root here (not a wildcard-open grant) is standard
# for an intra-account role: the account's own IAM policies still gate who
# is actually allowed to call sts:AssumeRole on it - see the sts:AssumeRole
# grant below, restricted to group2. This is different from roleC's trust
# policy (account-b.tf), which is a genuine cross-account boundary where
# the trust policy is the ONLY gate - see NOTES.md Q2.
data "aws_iam_policy_document" "roleA_permissions" {
  statement {
    effect  = "Allow"
    actions = ["*"]
    # Every AWS service except IAM.
    not_actions = ["iam:*"]
    resources   = ["*"]
  }
}

resource "aws_iam_role" "roleA" {
  provider           = aws.account_a
  name               = "roleA"
  assume_role_policy = data.aws_iam_policy_document.roleA_trust.json
}

resource "aws_iam_role_policy" "roleA_permissions" {
  provider = aws.account_a
  name     = "roleA-admin-except-iam"
  role     = aws_iam_role.roleA.id
  policy   = data.aws_iam_policy_document.roleA_permissions.json
}

# Only group2 (full admins) may actually assume roleA.
data "aws_iam_policy_document" "group2_can_assume_roleA" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.roleA.arn]
  }
}

resource "aws_iam_group_policy" "group2_assume_roleA" {
  provider = aws.account_a
  name     = "allow-assume-roleA"
  group    = aws_iam_group.group2.name
  policy   = data.aws_iam_policy_document.group2_can_assume_roleA.json
}

# --- roleB: only permission is assuming a role in Account B ------------------
data "aws_iam_policy_document" "roleB_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_a_id}:root"]
    }
  }
}

data "aws_iam_policy_document" "roleB_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::${var.account_b_id}:role/roleC"]
  }
}

resource "aws_iam_role" "roleB" {
  provider           = aws.account_a
  name               = "roleB"
  assume_role_policy = data.aws_iam_policy_document.roleB_trust.json
}

resource "aws_iam_role_policy" "roleB_permissions" {
  provider = aws.account_a
  name     = "roleB-assume-roleC-only"
  role     = aws_iam_role.roleB.id
  policy   = data.aws_iam_policy_document.roleB_permissions.json
}

# Same pattern as roleA: gate who may actually assume roleB via an
# in-account IAM grant. Here that's group1 (the automation identities that
# need to hop into Account B), not group2.
data "aws_iam_policy_document" "group1_can_assume_roleB" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.roleB.arn]
  }
}

resource "aws_iam_group_policy" "group1_assume_roleB" {
  provider = aws.account_a
  name     = "allow-assume-roleB"
  group    = aws_iam_group.group1.name
  policy   = data.aws_iam_policy_document.group1_can_assume_roleB.json
}
