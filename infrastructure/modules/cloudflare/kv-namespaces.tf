resource "cloudflare_workers_kv_namespace" "tenants" {
  count = contains(["sandbox", "prod"], var.environment) ? 1 : 0

  account_id = var.cloudflare_account_id
  title      = "${var.environment}-tenants-kv"
}
