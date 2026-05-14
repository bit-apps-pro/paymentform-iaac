terraform {
  required_version = ">= 1.8"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
  }
}

resource "hcloud_network" "main" {
  count    = var.enabled ? 1 : 0
  name     = "${var.resource_prefix}-network"
  ip_range = var.ip_range

  labels = merge(var.standard_tags, {
    environment = var.environment
    region      = var.network_zone
  })
}

resource "hcloud_network_subnet" "main" {
  count        = var.enabled ? 1 : 0
  network_id   = hcloud_network.main[0].id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = var.subnet_ip_range
}
