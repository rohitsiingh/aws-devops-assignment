variable "aws_region" {
  description = "AWS region to provision resources in."
  type        = string
  default     = "us-east-1"
}

# ---------------------------------------------------------------------------
# Single input variable that drives all 5 (or more) EC2 instances.
# Each map key is a logical instance name (used for tagging + outputs),
# each value carries everything that varies between instances:
# instance type, root volume type/size, key pair, and ownership tags.
# ---------------------------------------------------------------------------
variable "instances" {
  description = "Map of EC2 instances to create, keyed by logical name."
  type = map(object({
    instance_type          = string
    key_name               = string
    root_volume_type       = string           # gp2 | gp3 | io1 | io2 | standard
    root_volume_size       = number           # GiB
    root_volume_iops       = optional(number) # required for io1/io2, ignored otherwise
    environment            = string           # e.g. dev / staging / prod
    owner                  = string           # e.g. team or individual name
    subnet_id              = optional(string)
    vpc_security_group_ids = optional(list(string), [])
  }))

  validation {
    condition = alltrue([
      for k, v in var.instances :
      contains(["gp2", "gp3", "io1", "io2", "standard"], v.root_volume_type)
    ])
    error_message = "root_volume_type must be one of: gp2, gp3, io1, io2, standard."
  }

  validation {
    condition = alltrue([
      for k, v in var.instances :
      contains(["io1", "io2"], v.root_volume_type) ? v.root_volume_iops != null : true
    ])
    error_message = "root_volume_iops must be set whenever root_volume_type is io1 or io2."
  }
}

# The map key (from var.instances) whose instance must not be destroyed
# without first removing the lifecycle guard in main.tf. See NOTES.md.
variable "protected_instance_name" {
  description = "Key from var.instances that is protected by lifecycle.prevent_destroy."
  type        = string
  default     = "database"
}

variable "ami_name_filter" {
  description = "Name filter used to look up the latest AMI for all instances."
  type        = string
  default     = "al2023-ami-*-x86_64"
}
