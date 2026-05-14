terraform {
  required_version = ">= 1.8"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
  }
}

locals {
  server_name     = "${var.resource_prefix}-${var.region}-db-replica"
  admin_source_ips = sort(distinct(length(var.admin_cidr_blocks) > 0 ? var.admin_cidr_blocks : ["0.0.0.0/0"]))
  db_source_ips    = sort(distinct(length(var.backend_private_cidrs) > 0 ? var.backend_private_cidrs : (var.backend_public_ipv4 != "" ? ["${var.backend_public_ipv4}/32"] : var.allowed_cidrs)))
}

resource "hcloud_ssh_key" "db" {
  count      = var.ssh_key_id == "" && var.ssh_public_key != "" ? 1 : 0
  name       = "${local.server_name}-key"
  public_key = var.ssh_public_key
}

resource "hcloud_volume" "data" {
  name     = "${local.server_name}-data"
  size     = var.volume_size_gb
  location = var.location
  format   = "ext4"

  labels = merge(var.standard_tags, {
    environment = var.environment
    region      = var.region
    service     = "database"
  })
}

resource "hcloud_server" "db_replica" {
  count       = var.enabled ? 1 : 0
  name        = local.server_name
  server_type = var.server_type
  image       = var.server_image
  location    = var.location
  ssh_keys    = var.ssh_key_id != "" ? [var.ssh_key_id] : (var.ssh_public_key != "" ? [hcloud_ssh_key.db[0].id] : [])

  user_data = templatefile("${path.module}/userdata-replica.sh", {
    primary_host       = var.primary_host
    primary_port       = var.primary_port
    db_password        = var.db_password
    os_username        = var.os_username
    os_user_public_key = var.os_user_public_key
  })

  labels = merge(var.standard_tags, {
    environment = var.environment
    region      = var.region
    service     = "database"
    role        = "replica"
  })
}

resource "hcloud_volume_attachment" "data" {
  count     = var.enabled ? 1 : 0
  volume_id = hcloud_volume.data.id
  server_id = hcloud_server.db_replica[0].id
  automount = true
}

resource "hcloud_server_network" "db_replica" {
  count      = var.enabled && var.network_id != "" ? 1 : 0
  server_id  = hcloud_server.db_replica[0].id
  network_id = tonumber(var.network_id)
}

resource "hcloud_firewall" "db" {
  name = "${local.server_name}-fw"

  rule {
    description     = "Allow SSH admin access"
    direction       = "in"
    protocol        = "tcp"
    port            = "22"
    source_ips      = local.admin_source_ips
    destination_ips = []
  }

  rule {
    description     = "Allow PostgreSQL replication access"
    direction       = "in"
    protocol        = "tcp"
    port            = "5432"
    source_ips      = local.db_source_ips
    destination_ips = []
  }

  labels = var.standard_tags
}

resource "hcloud_firewall_attachment" "db" {
  count       = var.enabled ? 1 : 0
  firewall_id = hcloud_firewall.db.id
  server_ids  = [hcloud_server.db_replica[0].id]
}
