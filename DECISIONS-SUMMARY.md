# Quick Architecture Decisions Reference

> **TL;DR**: Answers to your key infrastructure questions

## Your Questions Answered

### ✅ Backend Multi-Region Deployment
**YES** - Deployed across 3 regions (us-east-1, eu-west-1, ap-southeast-1)
- Route53 latency-based routing
- Automatic failover
- ECS with auto-scaling

### ✅ Client Global CDN Deployment  
**YES** - CloudFront CDN with 300+ edge locations
- S3 origin
- < 50ms latency worldwide
- Automatic SSL

### ✅ Renderer Global CDN Deployment
**YES** - CloudFront CDN
- S3 origin for static assets
- Backend API for dynamic rendering
- Wildcard subdomain routing

### 🔄 Wildcard vs On-Demand DNS

**USE WILDCARD SUBDOMAINS** ✅ (Default for all tenants)

```
DNS: *.renderer.yourdomain.com → CloudFront
Example: tenant1.renderer.yourdomain.com
```

**Why:**
- ✅ Instant tenant provisioning (zero DNS changes)
- ✅ Unlimited scalability
- ✅ No API rate limits
- ✅ Zero per-tenant cost

**Use Cloudflare API Only For:**
- Enterprise customers with custom domains
- White-label requirements
- Premium tier (requires approval)

### ✅ Traefik as Reverse Proxy
**YES** - Traefik for:
- Automatic service discovery
- Multi-tenant subdomain routing
- SSL termination (development)
- Dynamic configuration

### ✅ FrankenPHP with libsql Extension
**YES** - Backend uses FrankenPHP
- Native Turso (libsql) support
- HTTP/2 & HTTP/3
- Worker mode for performance
- 3-5x better throughput than PHP-FPM

### 🗄️ Central DB: Neon

**YES** - Neon serverless PostgreSQL
- 75% cheaper than RDS
- Auto-scaling
- Zero management
- Use for: accounts, billing, tenant registry

### 🗄️ Tenant DB: Turso

**YES** - Turso edge SQLite
- Per-tenant databases
- Edge replication (< 10ms latency)
- Cost-effective
- Use for: forms, submissions, tenant configs

### 📦 Docker Images Storage

**USE GITHUB CONTAINER REGISTRY (GHCR)** ✅

**Cost Comparison (10GB storage, 50GB transfer/month):**
- **GHCR**: $0-25/month (500MB free, generous free tier)
- AWS ECR: $50-100/month (no free tier, cross-region costs)
- GCR: $50-80/month (no free tier)

**Setup:**
```bash
# Build and push
docker build -t ghcr.io/org/paymentform-backend:latest .
echo $GITHUB_TOKEN | docker login ghcr.io -u org --password-stdin
docker push ghcr.io/org/paymentform-backend:latest
```

**Use ECR only if:**
- Storage exceeds 100GB
- AWS-native compliance required
- Heavy cross-region replication within AWS

## Implementation Checklist

### Immediate Setup (Week 1)
- [ ] Create Neon account and central database
- [ ] Create Turso account and configure edge locations
- [ ] Setup GitHub Container Registry
- [ ] Configure Cloudflare DNS with wildcard record
- [ ] Deploy Traefik configuration

### Infrastructure Setup (Week 2-3)
- [ ] Deploy multi-region backend (3 regions)
- [ ] Configure Route53 health checks
- [ ] Setup CloudFront distributions (client + renderer)
- [ ] Configure S3 buckets and policies
- [ ] Deploy ECS clusters with auto-scaling

### Production Readiness (Week 4)
- [ ] Test failover scenarios
- [ ] Load testing with multi-tenancy
- [ ] Setup monitoring and alerts
- [ ] Document runbooks
- [ ] Train team on deployment process

## Cost Estimates

| Environment | Monthly Cost | Notes |
|-------------|-------------|-------|
| **Development** | $60-100 | Single region, minimal resources |
| **Staging** | $300-500 | Multi-region, production-like |
| **Production** | $800-1500+ | Full HA, auto-scaling, traffic-dependent |

**Cost Breakdown (Production):**
- ECS/EC2: $400-800
- Neon DB: $100-200
- Turso: $50-150
- CloudFront: $50-150
- ALB/Route53: $50-100
- S3/Storage: $20-50
- Secrets/Misc: $20-50

## Key Files & Documentation

- **Main README**: `./README.md`
- **Architecture Details**: `./docs/architecture.md`
- **Full Decision Log**: `./docs/architectural-decisions.md`
- **Cost Estimation Guide**: `./docs/cost-estimation.md`
- **Deployment Guide**: `./docs/deployment-guide.md`
- **Disaster Recovery**: `./docs/disaster-recovery.md`

## Quick Commands

```bash
# Initialize infrastructure
make init ENV=prod

# Plan deployment
make plan ENV=prod

# Deploy
make apply ENV=prod

# Estimate costs
make cost-estimate ENV=prod

# Run security scan
make security-scan

# Deploy with Ansible
ansible-playbook -i ansible/inventory/production ansible/playbooks/deploy-backend.yml
```

## Contact & Support

- **Documentation**: `./docs/` directory
- **Quick Start**: `make help`
- **Issues**: Check existing docs first, then reach out to infrastructure team

---

**Last Updated**: February 2026  
**Quick Reference**: Keep this file bookmarked for fast answers
