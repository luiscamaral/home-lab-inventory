# CI/CD Scripts for Dockermaster

This directory contains comprehensive CI/CD automation scripts for dockermaster services.

## 📋 Quick Reference

### Scripts Overview

| Script | Purpose | Usage |
|--------|---------|--------|
| [`deploy-service.sh`](./deploy-service.sh) | Deploy services with health checks and rollback | `./deploy-service.sh vault` |
| [`health-check.sh`](./health-check.sh) | Comprehensive health monitoring | `./health-check.sh --json` |
| [`vault-integration.sh`](./vault-integration.sh) | Vault secret management | `./vault-integration.sh get-secret service/key` |

## 🚀 Common Operations

### Deploy a Service
```bash
# Basic deployment
./deploy-service.sh vault

# Deployment with verbose output
./deploy-service.sh --verbose --timeout 900 portainer

# Dry run to see what would happen
./deploy-service.sh --dry-run --skip-backup nginx-rproxy
```

### Check Service Health
```bash
# Check all services
./health-check.sh

# Check specific services with details
./health-check.sh --detailed vault portainer github-runner

# Continuous monitoring
./health-check.sh --continuous --interval 30
```

### Manage Secrets with Vault
```bash
# Authenticate with Vault
./vault-integration.sh auth

# Get a secret
./vault-integration.sh get-secret github-runner/github-token

# Set a secret
./vault-integration.sh set-secret vault/admin-password password=newpass

# Generate .env file from secrets
./vault-integration.sh generate-env portainer --output /tmp/portainer.env
```

## ⚡ Quick Troubleshooting

### Service Won't Start
```bash
# Check service status
./health-check.sh service-name

# Deploy with force flag
./deploy-service.sh --force service-name

# Check logs
cd /nfs/dockermaster/docker/service-name
docker compose logs --tail=50
```

### Health Check Failures
```bash
# Detailed health check with debugging
./health-check.sh --verbose --detailed service-name

# Skip problematic checks
./health-check.sh --no-network-check --no-endpoint-check
```

### Vault Issues
```bash
# Check Vault health
./vault-integration.sh health-check

# Re-authenticate
./vault-integration.sh auth --verbose
```

## 🔧 Script Options

### deploy-service.sh Options
- `--verbose` - Enable detailed output
- `--dry-run` - Show what would be deployed
- `--force` - Deploy even if health checks fail
- `--skip-backup` - Skip pre-deployment backup
- `--skip-health-check` - Skip post-deployment validation
- `--timeout SECONDS` - Deployment timeout

### health-check.sh Options
- `--json` - JSON output format
- `--detailed` - Include resource metrics
- `--continuous` - Continuous monitoring mode
- `--interval SECONDS` - Monitoring interval
- `--exit-on-unhealthy` - Exit with error if unhealthy

### vault-integration.sh Options
- `--format FORMAT` - Output format (json, env, yaml)
- `--output FILE` - Write to file
- `--verbose` - Detailed logging
- `--force` - Skip confirmations

## 📊 Output Examples

### Health Check JSON Output
```json
{
  "timestamp": "2025-08-29T14:30:15Z",
  "services": [
    {
      "service": "vault",
      "overall_status": "healthy",
      "container_health": "healthy",
      "endpoint_health": "healthy",
      "network_health": "healthy",
      "containers": {"running": 2, "total": 2},
      "metrics": {"cpu_percent": 15.2, "container_count": 2}
    }
  ]
}
```

### Deployment Report
```json
{
  "service": "vault",
  "deployment": {
    "status": "success",
    "time_seconds": 180,
    "backup_id": "backup-20250829-143022"
  },
  "health_check": {
    "performed": true,
    "status": "passed",
    "time_seconds": 45
  }
}
```

## 🚨 Emergency Commands

### Emergency Rollback
```bash
# Rollback specific services to last known good state
gh workflow run emergency-rollback.yml \
  -f services="vault,portainer" \
  -f rollback_target="last-known-good" \
  -f reason="Emergency rollback required"
```

### Manual Service Recovery
```bash
# Stop service
cd /nfs/dockermaster/docker/service-name
docker compose down --timeout 30

# Restore from backup
cp /tmp/backup-*/service-name-docker-compose.yml.bak docker-compose.yml

# Restart service
docker compose up -d
```

## 📚 Integration with GitHub Actions

These scripts are designed to work with GitHub Actions workflows:

### In Workflows
```yaml
- name: Deploy service
  run: |
    scripts/cicd/deploy-service.sh ${{ matrix.service }}

- name: Health check
  run: |
    scripts/cicd/health-check.sh --exit-on-unhealthy

- name: Load secrets
  run: |
    scripts/cicd/vault-integration.sh generate-env ${{ matrix.service }} -o .env
```

### Environment Variables
```bash
# Common environment variables used by scripts
export DEPLOY_PATH="/nfs/dockermaster/docker"
export VAULT_ADDR="http://vault.d.lcamaral.com"
export LOG_LEVEL="INFO"
export DEPLOYMENT_TIMEOUT="600"
```

## 🔗 Related Documentation

- [CI/CD Pipeline Documentation](../docs/cicd-pipeline.md) - Complete pipeline overview
- [Service Matrix](../docs/service-matrix.md) - Service inventory and status
- [Vault Integration Plan](../docs/vault-integration-plan.md) - Secret management setup

---

**Quick Help**: Run any script with `--help` for detailed usage information and examples.
