output "network_id" {
  value = var.enabled ? try(hcloud_network.main[0].id, "") : ""
}

output "subnet_id" {
  value = var.enabled ? try(hcloud_network_subnet.main[0].id, "") : ""
}

output "network_ip_range" {
  value = var.enabled ? try(hcloud_network.main[0].ip_range, "") : ""
}
