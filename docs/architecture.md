# Payment Form Multi-Region IaC Documentation

## Architecture Overview

This Infrastructure as Code (IaC) implements a globally distributed deployment for the Payment Form application with the following characteristics:

- **Backend**: Multi-region deployment (US East, EU West, Asia Pacific) using FrankenPHP with libsql extension
- **Client Dashboard**: Global CDN deployment via CloudFront for worldwide low-latency access
- **Renderer (Multi-tenant)**: Global CDN deployment via CloudFront for ultra-fast form rendering
- **Databases**: Neon serverless PostgreSQL for central data + Turso edge databases for tenant data
- **Storage**: S3 with CloudFront CDN for global asset delivery
- **Load Balancing**: Regional ALBs with Route53 latency-based routing for backend services
- **Reverse Proxy**: Traefik for automatic service discovery and multi-tenant subdomain routing

## Directory Structure

```
paymentform-iac/
├── infrastructure/               # Main infrastructure module
│   ├── modules/                 # Reusable modules
│   │   ├── neon/               # Neon serverless PostgreSQL
│   │   ├── turso/              # Turso edge databases
│   │   ├── networking/         # VPC, subnets, security groups
│   │   ├── compute/            # ECS, ALB, auto-scaling
│   │   ├── storage/            # S3, CloudFront CDN
│   │   ├── security/           # IAM, KMS, encryption
│   │   └── alb/                # Application Load Balancers
│   │
│   ├── environments/           # Environment-specific configs
│   │   ├── dev/               # Development environment
│   │   ├── staging/           # Staging environment
│   │   └── prod/              # Production environment
│   │
│   └── live/                  # Deployed infrastructure configs
│       ├── global/            # Global resources (CDN, DNS)
│       └── regional/          # Region-specific backend services
│           ├── us-east-1/    # US backend region
│           ├── eu-west-1/    # EU backend region
│           └── ap-southeast-1/ # APAC backend region
│
├── ansible/                   # Configuration management
│   ├── playbooks/            # Deployment playbooks
│   ├── roles/                # Ansible roles
│   ├── inventory/            # Inventory definitions
│   └── vars/                 # Variable files
│
├── local/                    # Local development
│   ├── docker-compose.*.yml  # Docker Compose files
│   └── localstack.yml        # LocalStack for AWS emulation
│
├── scripts/                  # Helper scripts
│   ├── deploy-local.sh
│   ├── validate.sh
│   └── rollback.sh
│
└── docs/                     # Documentation
    ├── architecture.md
    ├── deployment-guide.md
    ├── secrets-management.md
    ├── monitoring-logging.md
    └── disaster-recovery.md
```

## Deployment Process

### Prerequisites

1. Install OpenTofu (>= v1.6) or Terraform
2. Install Ansible (>= v2.10)
3. Configure AWS CLI with appropriate permissions
4. Setup Neon account ([Sign up](https://neon.tech)) - Central PostgreSQL database
5. Setup Turso account ([Sign up](https://turso.tech)) - Edge tenant databases
6. Configure Cloudflare for DNS and CDN
7. Setup GitHub Container Registry for Docker images

### Backend Technology

**FrankenPHP** - Modern PHP application server with built-in features:
- Native libsql extension for Turso database support
- HTTP/2 and HTTP/3 support
- Built-in worker mode for better performance
- Lower memory footprint than traditional PHP-FPM

### Multi-Region Backend Deployment Steps

1. **Initialize OpenTofu**:
   ```bash
   cd iaac/
   make init ENV=prod
   ```

2. **Plan the infrastructure**:
   ```bash
   make plan ENV=prod
   ```

3. **Deploy the infrastructure**:
   ```bash
   make apply ENV=prod
   ```

4. **Deploy applications using Ansible**:
   ```bash
   ansible-playbook -i ansible/inventory/production ansible/playbooks/deploy-backend.yml
   ansible-playbook -i ansible/inventory/production ansible/playbooks/deploy-client.yml
   ansible-playbook -i ansible/inventory/production ansible/playbooks/deploy-renderer.yml
   ```

### Regional Deployment Order

For proper dependencies, deploy in this order:

1. **Global Networking**: Route53 zones, ACM certificates, CloudFront distributions
2. **Databases**: Neon PostgreSQL (central), Turso configuration (edge tenants)
3. **Storage**: S3 buckets with CloudFront CDN integration
4. **Backend Services**: Multi-region ECS deployment (us-east-1, eu-west-1, ap-southeast-1)
5. **Frontend Assets**: Upload to S3, invalidate CloudFront caches

## Traffic Routing Strategy

The architecture implements intelligent global traffic routing:

1. **Backend Services (Multi-Region)**:
   - Route53 latency-based routing directs API requests to nearest backend region
   - Health checks ensure failover to healthy regions
   - Regions: us-east-1, eu-west-1, ap-southeast-1

2. **Frontend Applications (Global CDN)**:
   - CloudFront edge locations serve client and renderer globally
   - Cached at 300+ edge locations worldwide
   - Origin: S3 bucket with optimized caching policies
   - Sub-second latency for users anywhere in the world

3. **Multi-Tenant Subdomain Routing**:
   - Wildcard DNS: `*.renderer.yourdomain.com` → CloudFront → Origin
   - Traefik backend inspects Host header for tenant identification
   - Automatic routing to correct tenant's Turso database

4. **Failover Protection**:
   - Backend: Automated failover between regions via Route53 health checks
   - Frontend: CloudFront handles origin failures automatically
   - Database: Neon automatic failover, Turso edge replication

## Security Features

- VPCs with private/public subnet separation
- Security groups restricting access to necessary ports only
- SSL/TLS encryption in transit
- KMS encryption at rest
- WAF protection at the edge
- IAM roles with least-privilege permissions
- Regular security scanning and monitoring

## Multi-Tenancy Support

The renderer service is designed for massive multi-tenancy:

### Subdomain Strategy

**Option 1: Wildcard Subdomains (RECOMMENDED)**
- Configuration: `*.renderer.paymentform.com` DNS record
- Example: `tenant1.renderer.paymentform.com`, `tenant2.renderer.paymentform.com`
- Benefits:
  - ✅ Instant tenant provisioning (no DNS changes required)
  - ✅ Unlimited scalability (no API rate limits)
  - ✅ Zero per-tenant costs
  - ✅ Simple Traefik configuration

**Option 2: On-Demand DNS Records via Cloudflare API**
- Create individual DNS records programmatically
- Example: `customdomain.com` → Managed via Cloudflare API
- Use Cases:
  - Enterprise customers requiring custom domains
  - White-label solutions
- Limitations:
  - ⚠️ API rate limits: 1200 requests per 5 minutes
  - ⚠️ DNS propagation delays
  - ⚠️ Additional provisioning complexity

**Implementation Decision**: Use wildcard subdomains as default. Implement on-demand DNS for premium/enterprise tier only.

### Data Isolation

- **Per-Tenant Turso Database**: Each tenant gets isolated SQLite database with edge replication
- **Shared Infrastructure**: Cost-efficient resource usage via logical separation
- **Security**: Row-level security policies prevent cross-tenant data access
- **Performance**: FrankenPHP libsql extension provides native database access

### Scalability

- Supports thousands of tenants on shared infrastructure
- Horizontal scaling via ECS auto-scaling
- Edge replication ensures low latency globally
- CloudFront caching reduces origin load

## Local Development

For local development and testing:

```bash
# Deploy backend only
./scripts/deploy-local.sh backend

# Deploy client with backend
./scripts/deploy-local.sh client

# Deploy renderer with backend
./scripts/deploy-local.sh renderer

# Deploy full application
./scripts/deploy-local.sh full
```

## Monitoring and Operations

- CloudWatch for AWS resource monitoring
- ECS Container Insights for container monitoring
- Application logs shipped to CloudWatch
- Health checks and alarms configured
- Automated scaling based on demand

## Disaster Recovery

- **Multi-region backend deployment** provides geographic redundancy
- **CloudFront CDN** ensures frontend availability even if origin is temporarily unavailable
- **Database replication**: 
  - Neon: Automated backups with point-in-time recovery
  - Turso: Edge replication across multiple regions
- **Automated backups** with configurable retention (7/14/30 days by environment)
- **Infrastructure as Code**: Rapid infrastructure recovery via OpenTofu
- **Blue-Green Deployments**: Zero-downtime updates using ECS task definition versioning
- **Regular disaster recovery testing** recommended

## Container Registry Strategy

### Recommended: GitHub Container Registry (GHCR)

**Pricing:**
- 500MB storage free
- $0.008/GB/month after free tier
- 1GB data transfer free
- $0.50/GB after free tier

**Benefits:**
- ✅ Most cost-effective for small-medium teams
- ✅ Native GitHub Actions integration
- ✅ Simple authentication with GitHub tokens
- ✅ No separate infrastructure to manage
- ✅ Public images are free (unlimited storage/bandwidth)

**Setup:**
```bash
# Build and push to GHCR
docker build -t ghcr.io/username/paymentform-backend:latest .
echo $GITHUB_TOKEN | docker login ghcr.io -u username --password-stdin
docker push ghcr.io/username/paymentform-backend:latest
```

### Alternative: AWS ECR

**Pricing:**
- $0.10/GB/month storage
- $0.09/GB data transfer (egress to internet)

**Use Cases:**
- ✅ Multi-region image replication required
- ✅ Compliance requires AWS-only infrastructure
- ✅ Heavy cross-region usage within AWS

**Trade-offs:**
- ❌ ~12x more expensive than GHCR for storage
- ❌ Egress charges can add up significantly

### Alternative: Google Artifact Registry

**Pricing:**
- $0.10/GB/month storage
- Regional egress charges vary

**Use Cases:**
- Only if using GCP services
- Not recommended for AWS-based deployments

### Decision Matrix

| Scenario | Recommended Registry |
|----------|---------------------|
| Startup/Small Team | GitHub Container Registry |
| AWS-Native Requirements | AWS ECR |
| Multi-Cloud Strategy | GitHub Container Registry |
| High-Volume Multi-Region | AWS ECR with replication |

**Default Choice**: GitHub Container Registry for optimal cost-to-benefit ratio.