variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "account_a_id" {
  type    = string
  default = "000000000000"
}

variable "account_b_id" {
  type    = string
  default = "111111111111"
}

variable "account_a_profile" {
  description = "Local AWS CLI profile / credentials used to manage Account A."
  type        = string
  default     = "account-a-admin"
}

variable "account_b_profile" {
  description = "Local AWS CLI profile / credentials used to manage Account B."
  type        = string
  default     = "account-b-admin"
}

# group2 members - named users with full console + CLI access.
variable "group2_users" {
  type    = list(string)
  default = ["alice", "bob"]
}

# The single named bucket in Account B that roleC gets full access to.
variable "shared_bucket_name" {
  type    = string
  default = "acme-account-b-shared-bucket"
}
