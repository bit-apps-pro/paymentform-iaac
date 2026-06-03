terraform {
  required_version = ">= 1.8"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

data "http" "cloudflare_ips_v4" {
  url = "https://www.cloudflare.com/ips-v4"
}

data "http" "cloudflare_ips_v6" {
  url = "https://www.cloudflare.com/ips-v6"
}

locals {
  server_name      = "${var.resource_prefix}-${var.region}-backend"
  admin_source_ips = sort(distinct(length(var.admin_cidr_blocks) > 0 ? var.admin_cidr_blocks : ["0.0.0.0/0"]))
  cloudflare_cidrs = length(var.cloudflare_cidrs) > 0 ? var.cloudflare_cidrs : concat(
    try(compact(split("\n", trimspace(data.http.cloudflare_ips_v4.response_body))), []),
    try(compact(split("\n", trimspace(data.http.cloudflare_ips_v6.response_body))), [])
  )
  edge_source_ips = sort(distinct(local.cloudflare_cidrs))

  rendered_userdata = templatefile("${path.module}/userdata.sh", {
    ghcr_username               = var.ghcr_username
    ghcr_token                  = var.ghcr_token
    container_image             = var.container_image
    backend_container_env_vars  = var.backend_container_env_vars
    service_type                = var.service_type
    valkey_password             = var.valkey_password
    valkey_memory_max           = var.valkey_memory_max
    renderer_container_image    = var.renderer_container_image
    renderer_container_env_vars = var.renderer_container_env_vars
    os_username                 = var.os_username
    os_user_public_key          = var.os_user_public_key
    deploy_script_content       = var.deploy_script_content
    traefik_host                = var.traefik_host
    acme_email                  = var.acme_email
    db_host                     = var.db_host
    caddy_env_vars              = var.caddy_env_vars
  })
}

resource "hcloud_ssh_key" "main" {
  count      = var.enabled && var.ssh_key_id == "" && var.ssh_public_key != "" ? 1 : 0
  name       = "${local.server_name}-key"
  public_key = var.ssh_public_key
}

resource "hcloud_server" "backend" {
  count       = var.enabled ? 1 : 0
  name        = local.server_name
  server_type = var.server_type
  image       = var.server_image
  location    = var.location
  ssh_keys    = var.ssh_key_id != "" ? [var.ssh_key_id] : (var.ssh_public_key != "" ? [hcloud_ssh_key.main[0].id] : [])

  user_data = local.rendered_userdata

  labels = merge(var.standard_tags, {
    environment = var.environment
    region      = var.region
    service     = "backend"
  })

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "hcloud_server_network" "backend" {
  count      = var.enabled && var.network_id != "" ? 1 : 0
  server_id  = hcloud_server.backend[0].id
  network_id = tonumber(var.network_id)
}

resource "hcloud_firewall" "backend" {
  count = var.enabled ? 1 : 0
  name  = "${local.server_name}-fw"

  rule {
    description     = "Allow SSH admin access"
    direction       = "in"
    protocol        = "tcp"
    port            = "22"
    source_ips      = local.admin_source_ips
    destination_ips = []
  }

  rule {
    description     = "Allow HTTP from Cloudflare"
    direction       = "in"
    protocol        = "tcp"
    port            = "80"
    source_ips      = local.edge_source_ips
    destination_ips = []
  }

  rule {
    description     = "Allow HTTPS from Cloudflare"
    direction       = "in"
    protocol        = "tcp"
    port            = "443"
    source_ips      = local.edge_source_ips
    destination_ips = []
  }

  labels = var.standard_tags
}

resource "hcloud_firewall_attachment" "backend" {
  count       = var.enabled ? 1 : 0
  firewall_id = hcloud_firewall.backend[0].id
  server_ids  = [hcloud_server.backend[0].id]
}

resource "null_resource" "ssh_apply_userdata" {
  count = var.enabled && var.ssh_private_key_path != "" ? 1 : 0

  triggers = {
    user_data_hash = md5(local.rendered_userdata)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      SERVER_IP="${var.enabled ? try(hcloud_server.backend[0].ipv4_address, "") : ""}"
      USER="${var.os_username}"
      KEY="${var.ssh_private_key_path}"

      if [ ! -f "$KEY" ]; then
        echo "SSH private key not found: $KEY; skipping Hetzner userdata update"
        exit 0
      fi

      echo "Applying updated userdata to Hetzner server $SERVER_IP via SSH (as root)"

      # SSH as root — Hetzner ssh_key_id is injected into /root/.ssh/authorized_keys
      # by default. The os user (${var.os_username}) is created BY the rendered
      # userdata script, so we can't depend on it existing for the connection.
      ssh -i "$KEY" \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          "root@$SERVER_IP" \
          "echo ${base64encode(local.rendered_userdata)} | base64 -d > /tmp/userdata-update.sh && bash /tmp/userdata-update.sh"
    EOT
  }

  depends_on = [hcloud_server.backend]
}
