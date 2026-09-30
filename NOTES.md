# NOTES

## Task 1 - Multi-Instance EC2 Provisioning

**Which instance is protected, and why:** the `database` instance (see
`task1-ec2-provisioning/terraform.tfvars.example`, key `protected_instance_name`
defaults to `"database"`). It's the one instance in this set holding state
that can't be trivially recreated - `web`, `app`, `cache`, and `batch` are
either stateless or rebuildable from a base image/config, but `database` sits
on `io2` storage precisely because it's carrying data that would be lost (or
very expensive to restore) if the instance were deleted by an errant
`terraform destroy` or a `terraform apply` that happens to force a
replacement. `lifecycle.prevent_destroy = true` makes Terraform refuse to
destroy it at plan time until someone deliberately removes that guard.

**Why there are two `aws_instance` resource blocks instead of one:**
Everything is still driven from a single input variable, `var.instances`
(see `variables.tf`) - but `lifecycle` meta-arguments, including
`prevent_destroy`, must be literal values in Terraform; they cannot reference
a variable or an expression like `each.value.prevent_destroy`. That means a
single `for_each` loop over `var.instances` cannot turn `prevent_destroy` on
for just one instance and off for the rest. The practical workaround (used
here in `main.tf`) is to partition the same map into `local.protected_instances`
and `local.standard_instances` and use two `for_each` blocks with identical
bodies except for the `lifecycle` block - not five hardcoded resources, just
one filter on one variable.

## Task 2 - Remote State & Locking

**What happens today, with local state, if two people run `apply` at the same time:**
Local state means there's no single shared, lockable source of truth - at
best (if the state file lives somewhere shared, e.g. a network drive or
committed to git) two applies can both read the same state as their starting
point, compute independent plans, and then both write their own updated state
back at the end. This is a classic read-modify-write race: whichever apply
finishes writing state last silently overwrites the other's changes. Concretely
this can mean:
- Terraform tries to create the same resource twice (e.g. two EC2 instances
  both believing they're the one true `web` instance), producing duplicate,
  untracked infrastructure and unexpected cost/security exposure.
- One apply's resource records get clobbered by the other's state write,
  leaving resources that were actually created in AWS but that Terraform's
  state no longer knows about ("orphaned" resources it can no longer manage,
  update, or clean up through Terraform).
- Two applies can also disagree about a destroy/replace, e.g. one apply
  changes an attribute that forces replacement while the other is mid-apply
  against the pre-change resource, corrupting the final state's view of reality.

**How the backend change prevents this:** the S3 backend
(`task1-ec2-provisioning/backend.tf`) gives everyone one shared, versioned
state file instead of separate local copies. The DynamoDB table adds locking
on top: before Terraform will modify state, it writes a lock record to the
table (keyed by the state file's path). If a second `apply` starts while that
lock item exists, Terraform fails immediately with "Error acquiring the state
lock" instead of proceeding - the second engineer has to wait until the first
apply finishes and releases the lock. Applies become serialized against a
single source of truth instead of racing each other.
(Aside: Terraform 1.10+ also supports native S3 locking via
`use_lockfile = true`, without DynamoDB - the assignment explicitly asks for
a DynamoDB table, so that's what's implemented here, but it's worth knowing
DynamoDB is no longer strictly required on newer Terraform versions.)

## Task 3 - Multi-Account IAM & Cross-Account Access

**1. Would you actually give `engine` and `ci` IAM users with access keys in
a real production setup?**

No, not if it can be avoided. Static IAM access keys are long-lived by
default, easy to leak (checked into repos, dumped in CI logs/build artifacts,
cached on a laptop), and require someone to remember to rotate them - in
practice they often don't get rotated for years. For `ci` specifically, the
much better pattern is OIDC federation: configure the CI platform (e.g.
GitHub Actions, GitLab CI) as an OIDC identity provider in AWS and let the
pipeline call `sts:AssumeRoleWithWebIdentity` to get short-lived, per-run
credentials scoped to a specific repo/branch/workflow - no long-lived secret
ever exists to leak. For `engine`, if that's an application/service identity
rather than a human, the equivalent is an IAM role bound to the actual
compute (an EC2 instance profile, an ECS task role, or a Lambda execution
role) instead of a user with access keys embedded in config or environment
variables. IAM users with access keys are best treated as a last resort for
legacy tooling that genuinely cannot assume a role, and even then paired with
mandatory rotation and access-key-age alerting. This assignment implements
`engine`/`ci` as IAM users because that's what was asked for, but a real
production build would replace both with role-based, short-lived credentials.

**2. In roleC's trust policy, why does it matter whether you trust the whole
Account A root vs. roleB's specific ARN?**

Because this is a genuine cross-account boundary, the trust policy on roleC
is the *only* gate Account B has - Account B has no visibility into, and no
control over, what IAM permissions exist inside Account A, now or in the
future. (Contrast this with `roleA`/`roleB` in `account-a.tf`, which trust
the Account A root - that's fine there because AWS also checks, in the same
account, whether the calling principal has an explicit `sts:AssumeRole`
grant; same-account assumption has two gates, cross-account assumption has
one.)

If roleC's trust policy names `arn:aws:iam::000000000000:root`, it's saying
"trust anything in Account A that Account A's admins have granted (or ever
will grant) permission to call `sts:AssumeRole` on this ARN." Account B's
security for that shared bucket now depends entirely on Account A's ongoing
IAM hygiene: any user, role, or automation in Account A that later picks up
an `sts:AssumeRole` grant for roleC - even by an unrelated team, even by
mistake, even via a compromised credential - can now get full access to the
bucket, and Account B would have no way to know until an audit. Naming
roleB's specific ARN instead means only that one, purpose-built role can ever
assume roleC, no matter what else changes inside Account A - the blast radius
of a mistake or compromise elsewhere in Account A stays contained. This is
least privilege applied to trust relationships, not just to permission
policies: scope trust to the narrowest principal that actually needs it.

## Task 4 - Least-Privilege Policy Writing

What was deliberately left out of `task4-least-privilege-policy/ci-policy.json`,
and why:

- **ECR repo/lifecycle management** (`ecr:CreateRepository`,
  `ecr:DeleteRepository`, `ecr:SetRepositoryPolicy`,
  `ecr:PutLifecyclePolicy`, etc.) - the pipeline pushes images to an
  already-existing repository; it has no business creating, deleting, or
  reconfiguring repos.
- **ECS service/task lifecycle management** (`ecs:CreateService`,
  `ecs:DeleteService`, `ecs:DeregisterTaskDefinition`, `ecs:RunTask`,
  `ecs:StopTask`) - the pipeline updates an *existing* service to point at a
  new task definition revision; it doesn't create or tear down services, or
  run arbitrary one-off tasks.
- **Unscoped `iam:PassRole`** - scoped to the two specific task-role ARNs the
  service actually uses, with a `iam:PassedToService = ecs-tasks.amazonaws.com`
  condition. An unscoped `iam:PassRole` is a classic privilege-escalation
  vector: it would let this credential pass *any* role (including far more
  privileged ones) to *any* service that accepts a passed role, not just ECS.
- **Any S3 write/delete on the artifacts bucket** (`s3:PutObject`,
  `s3:DeleteObject`, `s3:PutBucketPolicy`) - the task explicitly says CI
  *reads* build artifacts from that bucket; something else owns writing to
  it, so no write/delete permissions are granted there.
- **Any IAM, EC2/VPC, or other-service permissions** - CI doesn't create or
  modify IAM entities, networking, or anything outside the three things it's
  actually asked to do.
- **Two unavoidable exceptions, called out explicitly in the policy:**
  `ecr:GetAuthorizationToken` and `ecs:RegisterTaskDefinition` must use
  `Resource: "*"` - AWS does not support resource-level permissions for
  either action, so this is an AWS API limitation, not a deliberate
  broadening of scope. Everything else is scoped to a specific repo, service,
  task-definition family, role ARN, or bucket.

## Task 5 - Find and Fix the Bug

See `task5-bugfix/before/main.tf` (broken, as given) and
`task5-bugfix/after/main.tf` (fixed).

**Bug 1 - wrong principal type in the trust policy.** The trust policy
identifies the principal as `arn:aws:iam::000000000000:user/roleB` - i.e. an
IAM *user* named `roleB`. But roleB (per Task 3) is an IAM *role*, not a
user, and its correct ARN is `arn:aws:iam::000000000000:role/roleB`. An IAM
user and an IAM role are different principal types with different ARN
namespaces (`user/...` vs `role/...`); `user/roleB` refers to a user that
doesn't exist (or, if one happened to exist with that name, to entirely the
wrong principal). AWS validates that the assume-role policy's principals are
real, resolvable entities, and even if it didn't reject this outright, roleB
(the role) would never match this principal at assume-role time - so roleB
could never actually assume roleC. The fix is to point at `role/roleB`.

**Bug 2 - overly broad permissions policy.** roleC's inline policy grants
`Action: "s3:*"` on `Resource: "*"` - that's full S3 access to *every bucket
in the account* (existing and future), not the one named bucket Task 3 calls
for ("roleC: full access to a single named S3 bucket"). Resource `"*"` is the
same class of mistake as trusting the account root in the trust policy: it
silently grants far more than intended. The fix scopes `Resource` to the
specific bucket's ARN and its objects (`arn:aws:s3:::<bucket>` and
`arn:aws:s3:::<bucket>/*"`), which is what "full access to a single named
bucket" actually requires - full access to that bucket, not to S3 in general.
