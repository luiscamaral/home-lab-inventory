# Portainer GitOps Configuration Guide

> **Note:** This document describes a webhook-based GitOps approach that was not implemented. The actual deployment model uses Terraform to manage Portainer stacks. See `terraform/portainer/README.md` for the current workflow.

**Project**: Dockermaster Recovery - Phase 5  
**Created**: 2025-08-29  
**Status**: Implementation Phase  
**Repository**: <https://github.com/luiscamaral/home-lab-inventory>

## 📊 Executive Summary

This document provides comprehensive guidance for implementing GitOps workflows using Portainer stack management. The solution enables automatic deployment of Docker services from Git repository changes, centralizing container management while maintaining infrastructure as code principles.

### Key Benefits

- ✅ **Automated Deployments**: Push to repository triggers automatic service updates
- ✅ **Centralized Management**: Single interface for all container operations  
- ✅ **Version Control**: Full audit trail of infrastructure changes
- ✅ **Rollback Capability**: Easy reversion to previous configurations
- ✅ **Environment Consistency**: Same configuration across all environments

## 🏗️ Architecture Overview

### Components

```
GitHub Repository ──→ Webhook ──→ Portainer ──→ Docker Daemon ──→ Services
     ↑                    ↓           ↑             ↓            ↑
     │                    └───────────┘             └────────────┘
     └── Manual Updates                          Monitoring/Logs
```

### GitOps Workflow

1. **Code Change**: Developer pushes to main branch
2. **Webhook Trigger**: GitHub sends webhook to Portainer
3. **Stack Update**: Portainer pulls latest compose file
4. **Service Deployment**: Docker containers updated with new configuration
5. **Health Check**: Services verified as healthy
6. **Notification**: Success/failure reported

## 📁 Directory Structure

```
inventory/
├── dockermaster/
│   ├── docker/
│   │   └── compose/
│   │       ├── calibre-server/
│   │       │   ├── docker-compose.portainer.yml    # Portainer-optimized compose
│   │       │   ├── portainer-stack-config.json     # Stack configuration
│   │       │   └── CALIBRE_PORTAINER_MIGRATION.md  # Migration docs
│   │       └── <service>/
│   │           ├── docker-compose.yml              # Original compose
│   │           ├── docker-compose.portainer.yml    # Portainer version
│   │           └── portainer-stack-config.json     # Stack config
│   └── stacks/
│       ├── templates/
│       │   ├── portainer-stack-template.yml        # Base template
│       │   └── stack-config-template.json          # Config template
│       └── environments/
│           └── production.env                      # Environment variables
├── scripts/
│   └── portainer/
│       ├── deploy-stack.sh                        # Stack deployment
│       ├── convert-to-stack.sh                    # Conversion utility
│       └── backup-stacks.sh                      # Backup procedures
└── docs/
    └── portainer-gitops.md                        # This document
```

## 🔧 Implementation Steps

### Phase 1: Repository Integration

#### 1.1 Access Portainer

1. Navigate to **<https://192.168.59.2:9000>**
2. Log in with administrator credentials
3. Select the appropriate endpoint (usually 'local' or 'dockermaster')

#### 1.2 Configure Git Repository Access

1. Go to **Settings** → **Git repositories**
2. Add new repository:
   - **Name**: `home-lab-inventory`
   - **URL**: `https://github.com/luiscamaral/home-lab-inventory`
   - **Authentication**: None (public repository)
   - **Branch**: `main`

### Phase 2: Stack Creation and Configuration

#### 2.1 Convert Services to Stacks

Use the conversion script to prepare existing services:

```bash
# Convert all services
./scripts/portainer/convert-to-stack.sh --all

# Convert specific service
./scripts/portainer/convert-to-stack.sh calibre-server

# Dry run to see what would be created
./scripts/portainer/convert-to-stack.sh --dry-run --all
```

#### 2.2 Deploy Stack to Portainer

```bash
# Get Portainer API token from UI: User account → Access tokens
export PORTAINER_TOKEN="your-api-token-here"

# Deploy stack
./scripts/portainer/deploy-stack.sh --token $PORTAINER_TOKEN calibre-server

# Force update existing stack
./scripts/portainer/deploy-stack.sh --token $PORTAINER_TOKEN --force nginx-rproxy
```

#### 2.3 Stack Configuration Template

Each service requires two files:

**Docker-compose.portainer.yml**:

```yaml
name: service-name

services:
  service-name:
    image: service:latest
    hostname: service-name
    container_name: service-name

    networks:
      - docker-servers-net

    ports:
      - "HOST_PORT:CONTAINER_PORT"

    volumes:
      - /nfs/service/data:/app/data
      - /nfs/service/config:/app/config

    environment:
      PUID: ${PUID:-1000}
      PGID: ${PGID:-1000}
      TZ: ${TZ:-UTC}

    restart: unless-stopped

    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:PORT/health"]
      interval: 30s
      timeout: 10s
      retries: 3

    labels:
      com.centurylinklabs.watchtower.enable: "true"
      com.docker.stack: "service-name"
      portainer.autodeploy: "true"

networks:
  docker-servers-net:
    external: true
    name: docker-servers-net
```

**portainer-stack-config.JSON**:

```json
{
  "name": "service-name",
  "composeFile": "dockermaster/docker/compose/service-name/docker-compose.portainer.yml",
  "repositoryUrl": "https://github.com/luiscamaral/home-lab-inventory",
  "repositoryReference": "refs/heads/main",
  "created": "2025-08-29",
  "migration_phase": "deployment",

  "env": [
    {
      "name": "PUID",
      "value": "1000"
    },
    {
      "name": "PGID",
      "value": "1000"
    },
    {
      "name": "TZ",
      "value": "UTC"
    }
  ],

  "gitops": {
    "enabled": true,
    "autoUpdate": true
  }
}
```

### Phase 3: Webhook Configuration

#### 3.1 Configure Portainer Webhooks

For each deployed stack:

1. Go to **Stacks** → Select stack → **Webhooks**
2. Generate webhook URL (format: `https://192.168.59.2:9000/api/webhooks/<id>`)
3. Copy webhook URL for GitHub configuration

#### 3.2 Configure GitHub Webhooks

1. Go to repository **Settings** → **Webhooks**
2. Add webhook:
   - **Payload URL**: Portainer webhook URL
   - **Content type**: `application/json`
   - **Secret**: Leave empty or set matching secret in Portainer
   - **Events**: Select "Just the push event"
   - **Active**: ✅ Checked

#### 3.3 Test Webhook Integration

```bash
# Make a test change
echo "# Test GitOps" >> docs/test-gitops.md
git add docs/test-gitops.md
git commit -m "test: GitOps webhook integration"
git push origin main

# Monitor Portainer logs for webhook receipt
# Check stack update in Portainer UI
```

## 🔒 Environment Variable Management

### 3.1 Standard Variables

All stacks should include these standard environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `PUID` | `1000` | Process User ID for file permissions |
| `PGID` | `1000` | Process Group ID for file permissions |
| `TZ` | `UTC` | Timezone setting |

### 3.2 Service-Specific Variables

Configure in Portainer UI or stack configuration:

```json
{
  "env": [
    {
      "name": "SERVICE_PORT",
      "value": "8080"
    },
    {
      "name": "DATABASE_URL",
      "value": "VAULT_REFERENCE"
    }
  ]
}
```

### 3.3 Vault Integration

For sensitive data, reference Vault secrets:

```yaml
environment:
  DATABASE_PASSWORD: ${VAULT_SECRET_PATH}
  API_KEY: ${VAULT_API_KEY}
```

## 🔄 Backup and Recovery Procedures

### 4.1 Automated Backups

```bash
# Backup all stacks and data
./scripts/portainer/backup-stacks.sh --token $PORTAINER_TOKEN

# Backup specific stack only
./scripts/portainer/backup-stacks.sh --token $PORTAINER_TOKEN --stack calibre-server

# Configuration only (skip data volumes)
./scripts/portainer/backup-stacks.sh --token $PORTAINER_TOKEN --skip-data
```

### 4.2 Backup Schedule

Automated backups run:

- **Daily**: Configuration backups at 02:00 UTC
- **Weekly**: Full data backups on Sundays at 01:00 UTC
- **Pre-deployment**: Before major changes

### 4.3 Backup Locations

```
/nfs/dockermaster/backups/portainer/
├── stack-backup-20250829_140000/
│   ├── backup-manifest.json
│   ├── stacks.json
│   ├── endpoints.json
│   └── stacks/
│       ├── calibre-server/
│       │   ├── stack-config.json
│       │   ├── docker-compose.yml
│       │   ├── environment.json
│       │   └── library-data.tar.gz
│       └── nginx-rproxy/
└── restore-instructions-20250829_140000.md
```

## 🚨 Rollback Procedures

### 5.1 Emergency Rollback (UI Method)

1. Access Portainer UI: **<https://192.168.59.2:9000>**
2. Go to **Stacks** → Select affected stack
3. Click **Editor** tab
4. Revert to previous version or paste known good configuration
5. Click **Update the stack**
6. Monitor deployment logs

### 5.2 Git-Based Rollback

```bash
# Revert to previous commit
git log --oneline -10  # Find last good commit
git revert <commit-hash>
git push origin main   # Triggers automatic deployment

# Or reset to specific commit (use with caution)
git reset --hard <commit-hash>
git push --force origin main
```

### 5.3 Service-Level Rollback

```bash
# Stop stack in Portainer
curl -X POST "https://192.168.59.2:9000/api/stacks/$STACK_ID/stop" \
  -H "Authorization: Bearer $PORTAINER_TOKEN"

# Restore from backup
cd /nfs/dockermaster/backups/portainer/stack-backup-<timestamp>/
tar -xzf <service>-data.tar.gz -C /nfs/dockermaster/

# Restart with previous configuration
./scripts/portainer/deploy-stack.sh --token $PORTAINER_TOKEN --force <service>
```

## 📊 Monitoring and Validation

### 6.1 Health Checks

Each service includes health check configuration:

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

### 6.2 Deployment Validation

After each deployment, verify:

- [ ] Stack status shows "active" in Portainer
- [ ] All containers are "running"
- [ ] Service endpoints respond to health checks
- [ ] Application functionality confirmed
- [ ] Resource usage within expected limits

### 6.3 Monitoring Integration

Services are configured for monitoring:

```yaml
labels:
  prometheus.scrape: "true"
  prometheus.port: "9090"
  prometheus.path: "/metrics"
```

## 🔧 Troubleshooting Guide

### Common Issues and Solutions

#### 7.1 Stack Deployment Fails

**Symptoms**: Stack shows "failed" status in Portainer
**Solutions**:

1. Check Git repository accessibility
2. Verify Docker-compose.portainer.yml syntax
3. Review environment variables for typos
4. Check container logs: Stacks → Stack → Containers → Logs

#### 7.2 Webhook Not Triggered

**Symptoms**: Git push doesn't trigger deployment
**Solutions**:

1. Verify webhook URL in GitHub settings
2. Check webhook delivery history in GitHub
3. Confirm webhook payload format
4. Review Portainer webhook logs

#### 7.3 Container Start Failures

**Symptoms**: Containers in "exited" state
**Solutions**:

1. Check volume paths exist and are accessible
2. Verify port availability: `netstat -tulpn | grep :PORT`
3. Review container environment variables
4. Check resource limits and host capacity

#### 7.4 Network Connectivity Issues

**Symptoms**: Service not accessible from expected IPs
**Solutions**:

1. Verify Docker-servers-net network exists: `docker network ls`
2. Check container network assignment
3. Confirm port mapping: `docker port <container>`
4. Test internal connectivity: `docker exec -it <container> ping <target>`

### 7.5 Log Locations

- **Portainer Stack Logs**: Stacks → Stack → Editor → View logs
- **Container Logs**: Containers → Container → Logs  
- **System Logs**: SSH to dockermaster → `journalctl -u docker`
- **Webhook Logs**: Portainer → Settings → Activity logs

## 🎯 Best Practices

### 8.1 Stack Design

- Use descriptive stack names matching service function
- Include comprehensive health checks
- Set appropriate resource limits
- Use external networks for multi-stack communication
- Include monitoring labels for observability

### 8.2 GitOps Workflow

- Make incremental changes in feature branches
- Test configurations in non-production first
- Include descriptive commit messages
- Tag releases for easy rollback reference
- Monitor deployments after pushing

### 8.3 Security Considerations

- Use Vault for sensitive configuration
- Restrict Portainer API token access
- Configure webhook secrets for validation
- Regularly rotate API tokens
- Audit deployment activities

### 8.4 Environment Management

- Use consistent variable naming conventions
- Document all service-specific variables
- Validate environment configurations before deployment
- Maintain separate configurations per environment
- Version control all environment definitions

## 📋 Implementation Checklist

### Phase 5.1: Repository Integration

- [ ] Portainer repository configured
- [ ] Git authentication working
- [ ] Repository pull successful

### Phase 5.2: Stack Templates

- [ ] Base template created and tested
- [ ] Service conversion script functional
- [ ] Configuration templates validated

### Phase 5.3: Webhook Configuration  

- [ ] Portainer webhooks configured
- [ ] GitHub webhooks configured
- [ ] Webhook delivery tested

### Phase 5.4: Environment Management

- [ ] Standard environment variables defined
- [ ] Service-specific variables documented
- [ ] Vault integration planned

### Phase 5.5: Backup Procedures

- [ ] Backup scripts created and tested
- [ ] Automated backup schedule configured
- [ ] Restore procedures documented and verified

### Phase 5.6: Rollback Procedures

- [ ] Emergency rollback procedures tested
- [ ] Git-based rollback validated
- [ ] Service-level recovery verified

## 📈 Success Metrics

- ✅ All services convertible to Portainer stacks
- ✅ GitOps workflow functional end-to-end
- ✅ Deployment time under 5 minutes per stack
- ✅ Zero service disruption during migration
- ✅ Backup/restore procedures validated
- ✅ Monitoring integration operational
- ✅ Team trained on new procedures

## 🔮 Future Enhancements

### Potential Improvements

1. **Multi-environment Support**: Staging/production separation
2. **Advanced Monitoring**: Custom dashboards and alerting
3. **Automated Testing**: Pre-deployment validation pipelines
4. **Blue-Green Deployments**: Zero-downtime deployment strategy
5. **Secret Rotation**: Automated credential management
6. **Resource Optimization**: Dynamic resource allocation

### Migration Roadmap

1. **Phase 1**: Core services (Vault, GitHub Runner, Portainer)
2. **Phase 2**: Infrastructure services (Nginx, DNS, Monitoring)  
3. **Phase 3**: Application services (Calibre, N8N, etc.)
4. **Phase 4**: Development and testing services
5. **Phase 5**: Optimization and advanced features

---

**Document Version**: 1.0  
**Last Updated**: 2025-08-29  
**Next Review**: 2025-09-29  
**Maintained By**: DevOps Team
