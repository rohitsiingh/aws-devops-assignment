data "aws_ami" "this" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = [var.ami_name_filter]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  # Split the single input variable into "protected" vs "everything else".
  # This split exists ONLY because of a hard Terraform constraint: the
  # `lifecycle` meta-argument (including prevent_destroy) must be a literal
  # value and cannot reference a variable, so it cannot be parameterized
  # per-instance inside one for_each block. See NOTES.md for the full
  # explanation. All instances still come from the same var.instances map -
  # nothing here is a hardcoded resource block.
  protected_instances = {
    for name, cfg in var.instances : name => cfg
    if name == var.protected_instance_name
  }

  standard_instances = {
    for name, cfg in var.instances : name => cfg
    if name != var.protected_instance_name
  }

  common_tags = {
    ManagedBy = "terraform"
  }
}

resource "aws_instance" "standard" {
  for_each = local.standard_instances

  ami                    = data.aws_ami.this.id
  instance_type          = each.value.instance_type
  key_name               = each.value.key_name
  subnet_id              = each.value.subnet_id
  vpc_security_group_ids = each.value.vpc_security_group_ids

  root_block_device {
    volume_type = each.value.root_volume_type
    volume_size = each.value.root_volume_size
    iops        = contains(["io1", "io2"], each.value.root_volume_type) ? each.value.root_volume_iops : null
    encrypted   = true
  }

  tags = merge(local.common_tags, {
    Name        = each.key
    Environment = each.value.environment
    Owner       = each.value.owner
  })
}

# Identical resource body to aws_instance.standard, EXCEPT for the
# lifecycle block. Kept as a separate resource purely because
# prevent_destroy cannot be driven by a variable inside a shared for_each.
resource "aws_instance" "protected" {
  for_each = local.protected_instances

  ami                    = data.aws_ami.this.id
  instance_type          = each.value.instance_type
  key_name               = each.value.key_name
  subnet_id              = each.value.subnet_id
  vpc_security_group_ids = each.value.vpc_security_group_ids

  root_block_device {
    volume_type = each.value.root_volume_type
    volume_size = each.value.root_volume_size
    iops        = contains(["io1", "io2"], each.value.root_volume_type) ? each.value.root_volume_iops : null
    encrypted   = true
  }

  tags = merge(local.common_tags, {
    Name        = each.key
    Environment = each.value.environment
    Owner       = each.value.owner
  })

  lifecycle {
    prevent_destroy = true
  }
}
