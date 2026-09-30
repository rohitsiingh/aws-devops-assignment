output "instance_ids" {
  description = "Map of instance name -> instance ID."
  value = merge(
    { for name, inst in aws_instance.standard : name => inst.id },
    { for name, inst in aws_instance.protected : name => inst.id },
  )
}

output "instance_private_ips" {
  description = "Map of instance name -> private IP address."
  value = merge(
    { for name, inst in aws_instance.standard : name => inst.private_ip },
    { for name, inst in aws_instance.protected : name => inst.private_ip },
  )
}
