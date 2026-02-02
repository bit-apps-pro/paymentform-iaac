# Submodule Workflow Deployment - Quick Checklist

## ✅ Pre-Deployment (Already Complete)

- [x] Cloudflare infrastructure created
- [x] Traefik configurations created
- [x] GitHub Actions workflows created (4 files)
- [x] Deployment guide written
- [x] Automation script created

## 🎯 Deployment Tasks (To Do)

### 1. Deploy Workflows to Submodules (~30 min)

#### Option A: Automated (Recommended)
```bash
cd /path/to/paymentform-docker
./iaac/scripts/deploy-workflows-to-submodules.sh
```
- [ ] Run script
- [ ] Follow prompts for backend
- [ ] Follow prompts for client
- [ ] Follow prompts for renderer
- [ ] Follow prompts for admin

#### Option B: Manual
- [ ] Deploy to backend repo
- [ ] Deploy to client repo
- [ ] Deploy to renderer repo
- [ ] Deploy to admin repo

### 2. Enable GitHub Actions (2 min per repo)

For each repository (backend, client, renderer, admin):
- [ ] Go to Settings → Actions → General
- [ ] Select "Allow all actions and reusable workflows"
- [ ] Select "Read and write permissions"
- [ ] Check "Allow GitHub Actions to create and approve pull requests"
- [ ] Click Save

### 3. Test Workflows (5 min per repo)

For each repository:
- [ ] Go to Actions tab
- [ ] Select "Build and Push" workflow
- [ ] Click "Run workflow"
- [ ] Select branch: main
- [ ] Click "Run workflow"
- [ ] Wait for completion (~2-3 min)
- [ ] Verify green checkmark ✅

### 4. Create First Releases (10 min)

For each repository:
- [ ] Backend: `gh release create v0.1.0 --generate-notes -R your-org/paymentform-backend`
- [ ] Client: `gh release create v0.1.0 --generate-notes -R your-org/paymentform-client`
- [ ] Renderer: `gh release create v0.1.0 --generate-notes -R your-org/paymentform-renderer`
- [ ] Admin: `gh release create v0.1.0 --generate-notes -R your-org/paymentform-admin`

Or use GitHub UI for each repo:
- [ ] Releases → Draft new release
- [ ] Tag: v0.1.0
- [ ] Target: main
- [ ] Generate release notes
- [ ] Publish

### 5. Verify Images (5 min)

```bash
# Check images in GHCR
docker pull ghcr.io/your-org/paymentform-backend:v0.1.0
docker pull ghcr.io/your-org/paymentform-backend:stable
docker pull ghcr.io/your-org/paymentform-client:stable
docker pull ghcr.io/your-org/paymentform-renderer:stable
docker pull ghcr.io/your-org/paymentform-admin:stable
```

- [ ] Backend image pulled successfully
- [ ] Client image pulled successfully
- [ ] Renderer image pulled successfully
- [ ] Admin image pulled successfully

### 6. Update Docker Compose (5 min)

Edit `docker-compose.yml` or create `docker-compose.prod.yml`:

```yaml
services:
  backend:
    image: ghcr.io/your-org/paymentform-backend:stable
  
  client:
    image: ghcr.io/your-org/paymentform-client:stable
  
  renderer:
    image: ghcr.io/your-org/paymentform-renderer:stable
```

- [ ] Update image references
- [ ] Commit changes
- [ ] Test locally with `docker-compose pull`

### 7. Deploy Cloudflare + Traefik Infrastructure

See main implementation docs:

- [ ] Deploy Terraform infrastructure
- [ ] Get EC2 IPs and update origin IPs
- [ ] Deploy Traefik to EC2 instances
- [ ] Verify DNS resolution
- [ ] Test SSL/TLS
- [ ] Verify health checks

## 📊 Success Criteria

All boxes checked above, plus:

- [ ] All 4 workflows running successfully
- [ ] All 4 releases created (v0.1.0)
- [ ] All images available in GHCR with `stable` tag
- [ ] Docker Compose can pull all images
- [ ] Cloudflare DNS resolving correctly
- [ ] Traefik routing working
- [ ] SSL certificates issued
- [ ] Application accessible via HTTPS

## 🆘 Troubleshooting

### Workflow fails
→ Check DEPLOYMENT-GUIDE.md troubleshooting section

### Images not accessible
→ Verify GHCR authentication and image visibility (public/private)

### Release not triggering workflow
→ Ensure workflow is committed to main branch before creating release

### DNS not resolving
→ Check Cloudflare zone configuration and nameservers

## 📚 Documentation References

- Full deployment: `iaac/docs/github-workflows-for-submodules/DEPLOYMENT-GUIDE.md`
- Quick commands: `iaac/docs/QUICK-REFERENCE.md`
- GHCR setup: `iaac/docs/github-registry-setup.md`
- Cloudflare: `iaac/docs/cloudflare-setup.md`
- Traefik: `iaac/docs/traefik-cloud-setup.md`

## ⏱️ Time Estimates

- Workflow deployment: 10 min (automated) or 20 min (manual)
- Enable Actions: 8 min (2 min × 4 repos)
- Test workflows: 20 min (5 min × 4 repos)
- Create releases: 10 min
- Verify images: 5 min
- Update compose: 5 min
- **Total: ~60 minutes**

---

**Current Status**: ✅ Ready to begin deployment  
**Last Updated**: 2026-02-02
