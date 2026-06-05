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
  server_name      = "${var.resource_prefix}-${var.region}-admin"
  admin_source_ips = sort(distinct(length(var.admin_cidr_blocks) > 0 ? var.admin_cidr_blocks : ["0.0.0.0/0"]))
  cloudflare_cidrs = concat(
    try(compact(split("\n", trimspace(data.http.cloudflare_ips_v4.response_body))), []),
    try(compact(split("\n", trimspace(data.http.cloudflare_ips_v6.response_body))), [])
  )
  edge_source_ips = sort(distinct(local.cloudflare_cidrs))

  # Pre-render env file contents in TF so the userdata script can dump them via
  # quoted heredocs. Avoids bash arg-parsing corruption for values containing
  # `"` or `\`. Laravel/vlucas dotenv reads `KEY="value"` with backslash escapes.
  admin_env_content = join("\n", [
    for k, v in var.admin_container_env_vars :
    v == null ? "" : format(
      "%s=\"%s\"",
      k,
      replace(replace(v, "\\", "\\\\"), "\"", "\\\"")
    )
  ])

  # docker-compose .env: literal KEY=VALUE; compose does not interpolate `$`
  # inside .env values, so no escaping needed except for backslash/quote.
  compose_env_content = join("\n", [
    "ADMIN_IMAGE=${var.admin_image}",
    "BACKEND_IMAGE=${var.backend_image}",
    "TRAEFIK_HOST=${var.traefik_host}",
    "ACME_EMAIL=${var.acme_email}",
    "VALKEY_PASSWORD=${var.valkey_password}",
    "LOCAL_DB_DATABASE=${var.local_db_database}",
    "LOCAL_DB_USERNAME=${var.local_db_username}",
    "LOCAL_DB_PASSWORD=${var.local_db_password}",
    "BACKEND_DB_CONNECTION=${var.backend_db_connection}",
    "BACKEND_DB_HOST=${var.backend_db_host}",
    "BACKEND_DB_PORT=${var.backend_db_port}",
    "BACKEND_DB_DATABASE=${var.backend_db_database}",
    "BACKEND_DB_USERNAME=${var.backend_db_username}",
    "BACKEND_DB_PASSWORD=${var.backend_db_password}",
    "SQS_KEY=${var.sqs_key}",
    "SQS_SECRET=${var.sqs_secret}",
    "SQS_PREFIX=${var.sqs_prefix}",
    "SQS_REGION=${var.sqs_region}",
  ])

  rendered_userdata = templatefile("${path.module}/userdata.sh", {
    ghcr_username               = var.ghcr_username
    ghcr_token                  = var.ghcr_token
    os_username                 = var.os_username
    os_user_public_key          = var.os_user_public_key
    deploy_script_content       = var.deploy_script_content
    compose_file_content        = var.compose_file_content
    admin_env_content           = local.admin_env_content
    compose_env_content         = local.compose_env_content
    local_db_username           = var.local_db_username
    local_db_password           = var.local_db_password
    backup_replication_password = var.backup_replication_password
    backup_bucket_name          = var.backup_bucket_name
    backup_bucket_endpoint      = var.backup_bucket_endpoint
    backup_bucket_access_key_id = var.backup_bucket_access_key_id
    backup_bucket_access_key    = var.backup_bucket_access_key
    backup_server_name          = var.backup_server_name
    backup_schedule             = var.backup_schedule
  })
}

resource "hcloud_server" "admin" {
  count       = var.enabled ? 1 : 0
  name        = local.server_name
  server_type = var.server_type
  image       = var.server_image
  location    = var.location
  ssh_keys    = var.ssh_key_id != "" ? [var.ssh_key_id] : []

  user_data = local.rendered_userdata

  labels = merge(var.standard_tags, {
    environment = var.environment
    region      = var.region
    service     = "admin"
  })

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "hcloud_server_network" "admin" {
  count      = var.enabled && var.network_id != "" ? 1 : 0
  server_id  = hcloud_server.admin[0].id
  network_id = tonumber(var.network_id)
}

resource "hcloud_firewall" "admin" {
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
    # Open :80 to the world so Let's Encrypt validators can hit
    # /.well-known/acme-challenge/* (HTTP-01). Traefik redirects all
    # non-ACME requests on :80 to :443, so this does not widen the
    # application surface — :443 stays Cloudflare-only below. LE
    # publishes its validator pool dynamically and does not offer a
    # stable CIDR list, so per-IP scoping is not viable.
    description     = "Allow HTTP for ACME HTTP-01 challenge"
    direction       = "in"
    protocol        = "tcp"
    port            = "80"
    source_ips      = ["0.0.0.0/0", "::/0"]
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

resource "hcloud_firewall_attachment" "admin" {
  count       = var.enabled ? 1 : 0
  firewall_id = hcloud_firewall.admin[0].id
  server_ids  = [hcloud_server.admin[0].id]
}

# Re-apply userdata to the running server when its content changes. The
# `hcloud_server.admin` lifecycle ignores `user_data` so Terraform never
# destroys/recreates the box on drift — this null_resource is the in-place
# update path: SSH in, write the rendered script, run it.
resource "null_resource" "ssh_apply_userdata" {
  count = var.enabled && var.ssh_private_key_path != "" ? 1 : 0

  triggers = {
    user_data_hash = md5(local.rendered_userdata)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      SERVER_IP="${var.enabled ? try(hcloud_server.admin[0].ipv4_address, "") : ""}"
      KEY="${var.ssh_private_key_path}"

      if [ ! -f "$KEY" ]; then
        echo "SSH private key not found: $KEY; skipping Hetzner userdata update"
        exit 0
      fi

      echo "Applying updated userdata to Hetzner admin $SERVER_IP via SSH (as root)"

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

  depends_on = [hcloud_server.admin]
}
