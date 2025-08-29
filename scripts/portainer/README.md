# Portainer GitOps Management Scripts

This directory contains automation scripts for managing Portainer stacks with GitOps workflows.

## 📁 Script Overview

### Core Management Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `deploy-stack.sh` | Deploy services to Portainer as GitOps-enabled stacks | `./deploy-stack.sh -t TOKEN service-name` |
| `convert-to-stack.sh` | Convert docker-compose.yml to Portainer-compatible stacks | `./convert-to-stack.sh --all` |
| `backup-stacks.sh` | Backup Portainer configurations and data volumes | `./backup-stacks.sh -t TOKEN` |
| `rollback-stack.sh` | Emergency rollback for failed deployments | `./rollback-stack.sh -t TOKEN service-name` |

## 🚀 Quick Start Guide

### 1. Preparation
```bash
# Ensure you have Portainer API token
# Get from Portainer UI: User account → Access tokens
export PORTAINER_TOKEN="your-api-token-here"

# Verify Portainer is accessible
curl -k https://192.168.59.2:9000/api/status
```

### 2. Convert Existing Services
```bash
# Convert all services to Portainer-compatible format
./convert-to-stack.sh --all

# Or convert individual service
./convert-to-stack.sh calibre-server
```

### 3. Deploy to Portainer
```bash
# Deploy converted stack
./deploy-stack.sh --token $PORTAINER_TOKEN calibre-server

# Force update if stack exists
./deploy-stack.sh --token $PORTAINER_TOKEN --force nginx-rproxy
```

### 4. Backup Configuration
```bash
# Backup all stacks and data
./backup-stacks.sh --token $PORTAINER_TOKEN

# Configuration only (faster)
./backup-stacks.sh --token $PORTAINER_TOKEN --skip-data
```

## 📜 Detailed Script Documentation

### deploy-stack.sh
Deploy a service to Portainer as a GitOps-enabled stack.

**Usage**:
```bash
./deploy-stack.sh [OPTIONS] <service_name>

Options:
  -t, --token TOKEN       Portainer API token (required)
  -e, --endpoint-id ID    Portainer endpoint ID (default: 1)
  -f, --force             Force update if stack exists
  -d, --dry-run           Show deployment plan without executing
  -v, --verbose           Verbose output
```

**Prerequisites**:
- Service must have `docker-compose.portainer.yml`
- Service must have `portainer-stack-config.json`
- Portainer must be accessible at https://192.168.59.2:9000

**Examples**:
```bash
# Basic deployment
./deploy-stack.sh --token abc123 calibre-server

# Force update existing stack
./deploy-stack.sh -t abc123 -f nginx-rproxy

# Dry run to see deployment plan
./deploy-stack.sh -t abc123 -d vault
```

### convert-to-stack.sh
Convert existing docker-compose.yml files to Portainer-compatible stacks.

**Usage**:
```bash
./convert-to-stack.sh [OPTIONS] <service_name>

Options:
  -f, --force     Overwrite existing Portainer files
  -d, --dry-run   Show what would be created
  -v, --verbose   Verbose output
  --all          Convert all services
```

**Output Files**:
- `docker-compose.portainer.yml` - Portainer-optimized compose file
- `portainer-stack-config.json` - Stack configuration and metadata

**Examples**:
```bash
# Convert all services
./convert-to-stack.sh --all

# Convert specific service
./convert-to-stack.sh nginx-rproxy

# Dry run to preview changes
./convert-to-stack.sh --dry-run --all
```

### backup-stacks.sh
Create comprehensive backups of Portainer stack configurations and data.

**Usage**:
```bash
./backup-stacks.sh [OPTIONS]

Options:
  -t, --token TOKEN       Portainer API token (required)
  -o, --output-dir DIR    Backup directory (default: /nfs/dockermaster/backups/portainer)
  -s, --stack STACK       Backup specific stack only
  --skip-data            Configuration only (no data volumes)
  --compression LEVEL    Compression level 1-9 (default: 6)
  -v, --verbose          Verbose output
```

**Backup Contents**:
- Stack configurations and metadata
- Environment variables
- Docker compose files
- Data volume contents (unless `--skip-data`)

**Examples**:
```bash
# Full backup of all stacks
./backup-stacks.sh --token abc123

# Configuration backup only
./backup-stacks.sh -t abc123 --skip-data

# Backup specific stack
./backup-stacks.sh -t abc123 -s calibre-server
```

### rollback-stack.sh
Emergency rollback capabilities for failed deployments.

**Usage**:
```bash
./rollback-stack.sh [OPTIONS] <service_name>

Options:
  -t, --token TOKEN           Portainer API token (required)
  -m, --method METHOD         git|backup|config (default: git)
  -b, --backup-timestamp TS   Specific backup to restore
  -c, --commit HASH           Git commit to rollback to
  -l, --list-backups          List available backups
  -f, --force                 Skip confirmation prompt
  --data-only                 Restore data volumes only
  --config-only               Restore configuration only
```

**Rollback Methods**:
- **git**: Revert repository to previous commit (recommended)
- **backup**: Restore from Portainer stack backup
- **config**: Reset to original docker-compose.yml

**Examples**:
```bash
# Git-based rollback (recommended)
./rollback-stack.sh --token abc123 calibre-server

# Restore from specific backup
./rollback-stack.sh -t abc123 -m backup -b 20250829_140000 nginx-rproxy

# List available backups
./rollback-stack.sh -l calibre-server

# Rollback to specific git commit
./rollback-stack.sh -t abc123 -m git -c a1b2c3d4 vault
```

## 🔧 Configuration Files

### docker-compose.portainer.yml
Portainer-optimized compose file with GitOps labels:

```yaml
name: service-name

services:
  service-name:
    image: service:latest
    hostname: service-name
    container_name: service-name
    
    networks:
      - docker-servers-net
    
    environment:
      PUID: ${PUID:-1000}
      PGID: ${PGID:-1000}
      TZ: ${TZ:-UTC}
    
    labels:
      com.centurylinklabs.watchtower.enable: "true"
      com.docker.stack: "service-name"
      portainer.autodeploy: "true"

networks:
  docker-servers-net:
    external: true
```

### portainer-stack-config.json
Stack metadata and configuration:

```json
{
  "name": "service-name",
  "composeFile": "dockermaster/docker/compose/service/docker-compose.portainer.yml",
  "repositoryUrl": "https://github.com/luiscamaral/home-lab-inventory",
  "repositoryReference": "refs/heads/main",
  "env": [
    {
      "name": "PUID",
      "value": "1000"
    }
  ],
  "gitops": {
    "enabled": true,
    "autoUpdate": true
  }
}
```

## 🔍 Troubleshooting

### Common Issues

#### Script Permission Denied
```bash
chmod +x scripts/portainer/*.sh
```

#### API Connection Failed
```bash
# Verify Portainer is accessible
curl -k https://192.168.59.2:9000/api/status

# Check API token
curl -k -H "Authorization: Bearer $TOKEN" https://192.168.59.2:9000/api/users/me
```

#### Stack Deployment Failed
1. Check docker-compose.portainer.yml syntax
2. Verify environment variables
3. Check volume paths exist
4. Review Portainer logs

#### Backup/Restore Issues
1. Verify backup directory permissions
2. Check available disk space
3. Ensure all services are stopped during restore

### Log Locations
- Script logs: stdout/stderr
- Portainer logs: https://192.168.59.2:9000 → Activity logs
- Container logs: Containers → Container → Logs
- System logs: `journalctl -u docker`

## 🔐 Security Considerations

### API Token Management
- Generate tokens with minimal required permissions
- Rotate tokens regularly
- Store tokens securely (not in scripts or version control)
- Use environment variables: `export PORTAINER_TOKEN="..."`

### Network Security
- Portainer accessible only from trusted networks
- Use HTTPS for all API communications
- Validate webhook sources

### Backup Security
- Encrypt sensitive backup data
- Secure backup storage locations
- Regular backup validation

## 📋 Prerequisites

### Required Tools
- `curl` - API communication
- `jq` - JSON processing
- `yq` - YAML processing (optional but recommended)
- `docker` - Container management
- `git` - Version control

### Installation
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install curl jq docker.io git

# Install yq (recommended)
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# macOS
brew install curl jq yq docker git
```

### Permissions
- User must have access to Portainer API
- Docker socket access (usually via docker group)
- Read/write access to backup directories
- Git repository push permissions (for git rollbacks)

## 📈 Best Practices

### Deployment Workflow
1. Test changes in development environment
2. Create backup before major changes
3. Use dry-run mode to validate deployment
4. Monitor deployment completion
5. Verify service functionality post-deployment
6. Document any issues or special procedures

### Backup Strategy
- Daily configuration backups
- Weekly full backups (including data)
- Monthly backup validation
- Offsite backup storage for critical services

### Monitoring
- Set up health checks for all services
- Monitor deployment success/failure rates
- Track resource usage trends
- Alert on backup failures

## 🔗 Related Documentation

- [Portainer GitOps Guide](../../docs/portainer-gitops.md) - Complete GitOps workflow
- [Service Templates](../../dockermaster/stacks/templates/) - Reusable templates
- [Environment Configurations](../../dockermaster/stacks/environments/) - Environment variables

---

**Last Updated**: 2025-08-29  
**Maintained By**: DevOps Team