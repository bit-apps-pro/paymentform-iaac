# Infrastructure Runbooks

Operational documentation for the PaymentForm production infrastructure.

## Guides

| Guide | Description |
|-------|-------------|
| [Deployment](deploy.md) | Prerequisites, bootstrap, plan/apply workflow, rollback, GitHub Actions |
| [Backend & Renderer Deploy](backend-deploy.md) | EC2/Hetzner backend deploy, container images, GitHub Actions, rollback |
| [Database Operations](database-operations.md) | PostgreSQL setup, EBS mount, replica promotion, barman backup/restore, WAL archiving |
| [CDN & R2 Storage](cdn-storage.md) | R2 buckets, CDN workers, S3-compatible API, adding regions |
| [CDN Worker](cdn-worker.md) | Regional CDN workers, R2 bucket binding, domain routing, configuration |
| [DNS & Routing](dns.md) | Cloudflare DNS records, geo-routing, WAF, rate limiting, cache rules, tunnel |
| [Client Dashboard](client.md) | Cloudflare Container deployment, image updates, env vars |
| [Savings Plans Setup](savings-plan-setup.md) | AWS Savings Plans: types, pricing, purchase steps, validation |
| [Database Replica Setup](database-replica-setup.md) | PostgreSQL streaming replication on any cloud provider |
| [Database Tunnel & VPN](database-tunnel-vpn.md) | Connect to PostgreSQL from remote regions via tunnel or VPN |
| [Performance Observe & Tune](performance-observe-tune.md) | Step-by-step runbook to observe and tune backend server, PostgreSQL, and Redis |
| [Troubleshooting](troubleshooting.md) | Common issues: EBS mount, PostgreSQL service, barman credentials, worker deployment |

## Quick Reference

```bash
make init          # Initialize OpenTofu
make plan          # Generate execution plan
make apply         # Apply planned changes
make state-list    # List all resources
make output        # Show outputs
```

## Architecture Summary

- **AWS (us-east-1)**: EC2 backend (ASG), PostgreSQL primary/replica, NLBs, SSM secrets, EBS volumes
- **Cloudflare**: Containers (client/renderer), R2 (multi-region uploads + SSL config), Workers (CDN), KV (tenants), DNS, Tunnels
- **Hetzner**: Backend servers in hel1 (EU) and sin1 (AP), PostgreSQL replicas via Cloudflare Tunnel
