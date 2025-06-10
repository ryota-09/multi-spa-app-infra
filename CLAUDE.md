# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Next.js multi-SPA application infrastructure project that implements a hybrid architecture:
- **Static content** (pages, assets) served from S3 via CloudFront with long-term caching
- **Dynamic content** (login pages, API routes) served from App Runner via CloudFront with no caching

## Architecture

### Hybrid Deployment Model
```
CloudFront (CDN)
├── /login* → App Runner (Next.js standalone, no cache)
├── /api/* → App Runner (API routes, no cache)  
└── /* → S3 (static export, cached)
```

### Key Components
- **CloudFront**: CDN with path-based routing
- **App Runner**: Containerized Next.js app for dynamic content
- **S3**: Static file hosting for pre-built pages
- **ECR**: Docker image registry
- **Terraform**: Infrastructure as Code

## Development Commands

### Environment Check (Run First)
```bash
./scripts/check-environment.sh dev
```

### Full Deployment
```bash
./scripts/deploy.sh dev latest
```

### Quick Deployments
```bash
# App only (Docker to App Runner)
./scripts/quick-deploy.sh app dev

# Static files only (to S3)
./scripts/quick-deploy.sh static dev

# Infrastructure only
./scripts/quick-deploy.sh infra dev

# Everything
./scripts/quick-deploy.sh full dev
```

### Frontend Build Commands
```bash
cd frontend

# Static build (for S3, excludes API routes)
npm run build:static

# Standalone build (for App Runner)  
npm run build:standalone

# Hybrid build (both static and standalone)
npm run build:hybrid

# Push to ECR
npm run ecr:push:dev
```

### Testing & Diagnostics
```bash
# Test routing after deployment
./scripts/test-routing.sh dev

# Debug CloudFront issues
./scripts/debug-cloudfront.sh dev

# Diagnose App Runner problems
./scripts/diagnose-app-runner.sh dev
```

### Cleanup
```bash
./scripts/cleanup.sh dev
```

## Terraform Structure

```
terraform/
├── main.tf              # Root module
├── modules/             # Reusable modules
│   ├── ecr/            # Docker registry
│   ├── s3/             # Static hosting + OAC
│   ├── app-runner/     # Container service
│   └── cloudfront/     # CDN + cache behaviors
└── environments/
    └── dev/            # Environment-specific config
        ├── main.tf
        ├── variables.tf
        ├── terraform.tfvars  # Your settings
        └── outputs.tf
```

## Next.js Configuration

The app uses environment variables to control build output:

- `STANDALONE=true`: Builds for App Runner (dynamic routes)
- `STANDALONE=false` (default): Builds for S3 (static export)

## Key File Patterns

### Build Scripts
- `frontend/scripts/build-static.js`: Excludes API routes for static build
- `frontend/scripts/build-hybrid.js`: Creates both builds with consistent hashing
- `frontend/scripts/push-to-ecr.sh`: Docker build and ECR push

### Deployment Scripts  
- `scripts/deploy.sh`: Full deployment with options
- `scripts/quick-deploy.sh`: Simplified deployment modes
- `scripts/deploy-frontend.sh`: Static files only

### Infrastructure
- `terraform/environments/dev/terraform.tfvars`: Environment configuration
- All modules use consistent tagging and naming conventions

## Common Workflows

### Making Code Changes
1. Run `./scripts/check-environment.sh dev`
2. Make changes to frontend code
3. Deploy with `./scripts/quick-deploy.sh app dev` (for dynamic) or `./scripts/quick-deploy.sh static dev` (for static)
4. Test with `./scripts/test-routing.sh dev`

### Infrastructure Changes
1. Modify Terraform files in `terraform/modules/` or `terraform/environments/dev/`
2. Deploy with `./scripts/deploy.sh dev latest` or `./scripts/quick-deploy.sh infra dev`
3. Verify with AWS console or `terraform show`

### Troubleshooting
- CloudFront issues: `./scripts/debug-cloudfront.sh dev`
- App Runner issues: `./scripts/diagnose-app-runner.sh dev`
- Full environment check: `./scripts/check-environment.sh dev`

## Cache Strategy

- **Static content** (`/*`): Long-term cache (up to 1 year)
- **API routes** (`/api/*`): No cache (TTL=0)
- **Login pages** (`/login*`): No cache (TTL=0)

## Lint and Type Checking

Frontend uses:
```bash
cd frontend
npm run lint      # ESLint
npm run build     # TypeScript check during build
```

## Environment Variables

Key variables in `terraform/environments/dev/terraform.tfvars`:
- `aws_region`: AWS region
- `project_name`: Resource naming prefix
- `app_runner_cpu`/`app_runner_memory`: Container specs
- `cloudfront_price_class`: CDN pricing tier
- `enable_cloudfront_logging`: Access logging toggle

## Platform Notes

- **M1/M2 Macs**: All Docker builds use `--platform linux/amd64` for App Runner compatibility
- **ECR Authentication**: Handled automatically in deployment scripts
- **CloudFront Invalidations**: Selective invalidation for static assets only to avoid costs