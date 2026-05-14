output "server_id" {
  value = var.enabled ? try(hcloud_server.backend[0].id, "") : ""
}

output "ipv4_address" {
  value = var.enabled ? try(hcloud_server.backend[0].ipv4_address, "") : ""
}

output "ipv6_address" {
  value = var.enabled ? try(hcloud_server.backend[0].ipv6_address, "") : ""
}

output "server_name" {
  value = var.enabled ? try(hcloud_server.backend[0].name, "") : ""
}

output "private_ipv4_address" {
  description = "Private IP on the attached Hetzner network (empty string if no network attached)"
  value       = var.enabled && var.network_id != "" ? try(hcloud_server_network.backend[0].ip, "") : ""
}
