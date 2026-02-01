# Subdomain Configuration Guide

This document outlines the subdomain structure for the Payment Form application across different environments.

## Overview

The application uses a consistent subdomain structure across all environments:
- **Backend API**: `api.<environment-domain>`
- **Client Dashboard**: `app.<environment-domain>`
- **Multi-tenant Renderer**: `*.<environment-domain>` (wildcard)

## Environment Subdomains

### Sandbox Environment (Public Testing)

**Base Domain**: `sandbox.paymentform.io`

| Service | Subdomain | Purpose | Example URLs |
|---------|-----------|---------|--------------|
| Backend API | `api.sandbox.paymentform.io` | RESTful API endpoints | `https://api.sandbox.paymentform.io/api/v1/...` |
| Client Dashboard | `app.sandbox.paymentform.io` | Admin/user dashboard | `https://app.sandbox.paymentform.io` |
| Multi-tenant Renderer | `*.sandbox.paymentform.io` | Tenant-specific forms | `https://tenant1.sandbox.paymentform.io`<br>`https://acme-corp.sandbox.paymentform.io` |

**DNS Configuration**:
```
A    api.sandbox.paymentform.io     → <ALB-IP>
A    app.sandbox.paymentform.io     → <CloudFront>
A    *.sandbox.paymentform.io       → <CloudFront>
```

**SSL Certificate**:
- Primary: `sandbox.paymentform.io`
- SANs: `api.sandbox.paymentform.io`, `app.sandbox.paymentform.io`, `*.sandbox.paymentform.io`

---

### Production Environment

**Base Domain**: `paymentform.io`

| Service | Subdomain | Purpose | Example URLs |
|---------|-----------|---------|--------------|
| Backend API | `api.paymentform.io` | Production API | `https://api.paymentform.io/api/v1/...` |
| Client Dashboard | `app.paymentform.io` | Production dashboard | `https://app.paymentform.io` |
| Multi-tenant Renderer | `*.paymentform.io` | Production forms | `https://tenant1.paymentform.io`<br>`https://acme-corp.paymentform.io` |

**DNS Configuration**:
```
A    api.paymentform.io     → <ALB-IP>
A    app.paymentform.io     → <CloudFront>
A    *.paymentform.io       → <CloudFront>
```

**SSL Certificate**:
- Primary: `paymentform.io`
- SANs: `api.paymentform.io`, `app.paymentform.io`, `*.paymentform.io`

---

### Development Environment (Local)

**Base Domain**: `dev.paymentform.local`

| Service | Subdomain | Purpose | Example URLs |
|---------|-----------|---------|--------------|
| Backend API | `api.dev.paymentform.local` | Dev API | `http://api.dev.paymentform.local:8021/api/v1/...` |
| Client Dashboard | `app.dev.paymentform.local` | Dev dashboard | `http://app.dev.paymentform.local:8021` |
| Multi-tenant Renderer | `*.dev.paymentform.local` | Dev forms | `http://tenant1.dev.paymentform.local:8021` |

**DNS Configuration** (via dnsmasq):
```
address=/dev.paymentform.local/127.0.0.1
```

---

## Infrastructure Setup

### CloudFront Distribution Configuration

#### Client Dashboard Distribution

```hcl
# app.sandbox.paymentform.io
resource "aws_cloudfront_distribution" "client" {
  aliases = ["app.${var.domain_name}"]
  
  origin {
    domain_name = aws_s3_bucket.client.bucket_regional_domain_name
    origin_id   = "client-origin"
  }
  
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.main.arn
    ssl_support_method  = "sni-only"
  }
}
```

#### Renderer Distribution (Wildcard)

```hcl
# *.sandbox.paymentform.io
resource "aws_cloudfront_distribution" "renderer" {
  aliases = ["*.${var.domain_name}"]
  
  origin {
    domain_name = aws_s3_bucket.renderer.bucket_regional_domain_name
    origin_id   = "renderer-origin"
  }
  
  # Proxy API requests to backend
  origin {
    domain_name = aws_alb.backend.dns_name
    origin_id   = "backend-origin"
    
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
    }
  }
  
  # Route /api/* to backend
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    target_origin_id = "backend-origin"
    
    cache_policy_id          = aws_cloudfront_cache_policy.api.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.api.id
  }
}
```

### Application Load Balancer Configuration

```hcl
# api.sandbox.paymentform.io
resource "aws_alb" "backend" {
  name               = "backend-${var.environment}"
  load_balancer_type = "application"
  
  # Multi-region deployment
  subnets = var.public_subnet_ids
}

resource "aws_route53_record" "backend_api" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "api.${var.domain_name}"
  type    = "A"
  
  alias {
    name                   = aws_alb.backend.dns_name
    zone_id                = aws_alb.backend.zone_id
    evaluate_target_health = true
  }
}
```

### Route53 Configuration

```hcl
# Hosted Zone
resource "aws_route53_zone" "main" {
  name = var.domain_name
}

# Backend API
resource "aws_route53_record" "api" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.api_subdomain
  type    = "A"
  
  alias {
    name                   = aws_alb.backend.dns_name
    zone_id                = aws_alb.backend.zone_id
    evaluate_target_health = true
  }
}

# Client Dashboard
resource "aws_route53_record" "app" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.app_subdomain
  type    = "A"
  
  alias {
    name                   = aws_cloudfront_distribution.client.domain_name
    zone_id                = aws_cloudfront_distribution.client.hosted_zone_id
    evaluate_target_health = false
  }
}

# Renderer (Wildcard)
resource "aws_route53_record" "renderer" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.renderer_subdomain
  type    = "A"
  
  alias {
    name                   = aws_cloudfront_distribution.renderer.domain_name
    zone_id                = aws_cloudfront_distribution.renderer.hosted_zone_id
    evaluate_target_health = false
  }
}
```

---

## Traefik Configuration (Local Development)

For local development, Traefik routes based on Host headers:

```yaml
# docker-compose.yml
services:
  traefik:
    command:
      - --providers.docker=true
      - --entrypoints.web.address=:80
    labels:
      - "traefik.enable=true"

  backend:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.backend.rule=Host(`api.dev.paymentform.local`)"
      - "traefik.http.services.backend.loadbalancer.server.port=8000"

  client:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.client.rule=Host(`app.dev.paymentform.local`)"
      - "traefik.http.services.client.loadbalancer.server.port=3000"

  renderer:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.renderer.rule=HostRegexp(`{subdomain:[a-z0-9-]+}.dev.paymentform.local`)"
      - "traefik.http.services.renderer.loadbalancer.server.port=3000"
```

---

## SSL Certificate Setup

### ACM Certificate Request

```bash
# Request certificate with wildcard
aws acm request-certificate \
  --domain-name "sandbox.paymentform.io" \
  --subject-alternative-names \
    "*.sandbox.paymentform.io" \
    "api.sandbox.paymentform.io" \
    "app.sandbox.paymentform.io" \
  --validation-method DNS \
  --region us-east-1  # CloudFront requires us-east-1
```

### DNS Validation

Add CNAME records provided by ACM to your Route53 hosted zone.

---

## Application Configuration

### Backend (.env)

```env
# Sandbox
APP_URL=https://api.sandbox.paymentform.io
APP_DOMAIN=sandbox.paymentform.io
FRONTEND_URL=https://app.sandbox.paymentform.io
RENDERER_URL=https://sandbox.paymentform.io

# Production
APP_URL=https://api.paymentform.io
APP_DOMAIN=paymentform.io
FRONTEND_URL=https://app.paymentform.io
RENDERER_URL=https://paymentform.io
```

### Client (.env)

```env
# Sandbox
NEXT_PUBLIC_API_URL=https://api.sandbox.paymentform.io
NEXT_PUBLIC_APP_URL=https://app.sandbox.paymentform.io

# Production
NEXT_PUBLIC_API_URL=https://api.paymentform.io
NEXT_PUBLIC_APP_URL=https://app.paymentform.io
```

### Renderer (.env)

```env
# Sandbox
NEXT_PUBLIC_API_URL=https://api.sandbox.paymentform.io

# Production
NEXT_PUBLIC_API_URL=https://api.paymentform.io
```

---

## CORS Configuration

Backend CORS should allow:

```php
// config/cors.php
'allowed_origins' => [
    'https://app.sandbox.paymentform.io',
    'https://*.sandbox.paymentform.io',  // All tenant subdomains
],
```

---

## Deployment Checklist

### Sandbox Environment

- [ ] Configure Route53 hosted zone for `sandbox.paymentform.io`
- [ ] Request ACM certificate with wildcard (`*.sandbox.paymentform.io`)
- [ ] Validate certificate via DNS
- [ ] Create CloudFront distributions (client + renderer)
- [ ] Deploy backend to ALB (`api.sandbox.paymentform.io`)
- [ ] Update DNS records (A records for api, app, wildcard)
- [ ] Configure CORS in backend
- [ ] Test all subdomains
- [ ] Enable Cloudflare proxy (orange cloud)
- [ ] Verify SSL certificates

### Production Environment

Follow same checklist as sandbox, but for `paymentform.io` domain.

---

## Troubleshooting

### "Certificate doesn't match domain"

**Issue**: SSL certificate not covering wildcard subdomain

**Solution**: Ensure certificate includes `*.{domain}` as SAN

### "Subdomain not resolving"

**Issue**: DNS record not propagated or incorrect

**Solution**: 
```bash
# Check DNS
dig api.sandbox.paymentform.io
dig app.sandbox.paymentform.io
dig tenant1.sandbox.paymentform.io

# Verify Cloudflare proxy status
# Should show Cloudflare IPs if proxied
```

### "CORS error from tenant subdomain"

**Issue**: Backend CORS not allowing wildcard subdomain

**Solution**: Update `config/cors.php` to include `*.sandbox.paymentform.io`

---

## References

- [AWS CloudFront Documentation](https://docs.aws.amazon.com/cloudfront/)
- [Route53 Wildcard Records](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/ResourceRecordTypes.html)
- [ACM Certificate Validation](https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html)
- [Traefik Host Rules](https://doc.traefik.io/traefik/routing/routers/#rule)
