output "server_id" {
  value = var.enabled ? try(hcloud_server.admin[0].id, "") : ""
}

output "ipv4_address" {
  value = var.enabled ? try(hcloud_server.admin[0].ipv4_address, "") : ""
}

output "ipv6_address" {
  value = var.enabled ? try(hcloud_server.admin[0].ipv6_address, "") : ""
}

output "enabled" {
  value = var.enabled ? true : false
}