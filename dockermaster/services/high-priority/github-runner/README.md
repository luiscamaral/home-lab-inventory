# GitHub Runner Service Documentation

## 📊 Service Overview

- **Service Name**: github-runner
- **Category**: CI/CD Infrastructure
- **Status**: Active (Healthy)
- **IP Address**: 192.168.59.0
- **External URL**: Not applicable (internal CI/CD service)

## 🚀 Description

Self-hosted GitHub Actions runner for the home-lab-inventory repository. This service enables CI/CD workflows to execute directly on the dockermaster server, providing access to local Docker services and deployment capabilities. The runner is configured with Docker-in-Docker support for building and deploying containerized applications.

## 🔧 Configuration

### Docker Compose Location
```
/nfs/dockermaster/docker/github-runner/docker-compose.yml
```

### Environment Variables
- **Required**:
  - `GITHUB_TOKEN`: Personal Access Token or GitHub App token with repo scope
  - `RUNNER_NAME`: Name identifier for the runner (default: dockermaster-runner)
- **Optional**:
  - `RUNNER_GROUP`: Runner group assignment (default: default)
  - `LABELS`: Comma-separated list of runner labels (default: self-hosted,linux,x64,dockermaster,docker)
  - `EPHEMERAL`: Clean environment after each run (default: false)
  - `DISABLE_AUTO_UPDATE`: Prevent automatic runner updates (default: false)

### Volumes
- `./work`: Runner work directory for job execution
- `./runner-data`: Configuration persistence and runner registration data
- `/var/run/docker.sock`: Docker socket for Docker-in-Docker operations
- `/nfs/dockermaster/docker`: Read-only access to deployment configurations

### Network Configuration
- **Network**: docker-servers-net (macvlan)
- **IP**: 192.168.59.0
- **Ports**: No external ports exposed (runner polls GitHub for jobs)
- **Hostname**: dockermaster-runner

## 🔐 Security

### Secrets Management
- Secrets stored in environment file: `/nfs/dockermaster/docker/github-runner/.env`
- **Migration needed**: GitHub token should be moved to Vault at `secret/dockermaster/github-runner/github-token`

### Access Control
- Authentication method: GitHub Personal Access Token
- Repository scope: `https://github.com/luiscamaral/home-lab-inventory`
- Security options: AppArmor unconfined for Docker operations

### Security Considerations
- Runner has access to Docker daemon (high privilege)
- Read-only access to deployment configurations
- Watchtower updates disabled for stability
- Portainer auto-deploy disabled to prevent service disruption

## 📈 Monitoring

### Health Checks
- **Endpoint**: Process check for `Runner.Listener`
- **Interval**: 30s
- **Timeout**: 10s
- **Retries**: 3
- **Start Period**: 60s

### Metrics
- **Prometheus**: No (consider adding GitHub Actions exporter)
- **Metrics endpoint**: Not available
- **Custom dashboards**: None configured

### Resource Limits
- **CPU Limit**: 2 cores
- **Memory Limit**: 4GB
- **CPU Reservation**: 0.5 cores
- **Memory Reservation**: 512MB

## 🔄 Backup Strategy

### Data Backup
- **Method**: Manual
- **Frequency**: As needed (runner registration data)
- **Location**: Configuration included in dockermaster repository

### Configuration Backup
- **Git repository**: Yes - included in dockermaster repo
- **Environment file**: Excluded from git (contains sensitive token)

## 🚨 Troubleshooting

### Common Issues
1. **Runner offline/disconnected**
   - **Symptoms**: Jobs queued but not executing, runner shows offline in GitHub
   - **Solution**: Check token validity and restart service

2. **Docker-in-Docker failures**
   - **Symptoms**: Build steps failing with Docker daemon errors
   - **Solution**: Verify Docker socket mount and AppArmor configuration

3. **Disk space issues**
   - **Symptoms**: Jobs failing with disk full errors
   - **Solution**: Clean work directory and old Docker images

### Log Locations
- **Container logs**: `docker logs github-runner-homelab`
- **Runner logs**: Available in container logs output
- **Job logs**: Visible in GitHub Actions web interface

### Recovery Procedures
1. **Service restart**: `cd /nfs/dockermaster/docker/github-runner && docker compose restart`
2. **Full rebuild**: `docker compose down && docker compose up -d`
3. **Re-registration**: Delete `./runner-data` and restart (requires token)

## 📝 Maintenance

### Updates
- **Update schedule**: Manual (Watchtower disabled)
- **Update procedure**: 
  1. Check for new image: `docker compose pull`
  2. Restart service: `docker compose up -d`
  3. Verify runner health in GitHub

### Dependencies
- **Required services**: Docker daemon, network (docker-servers-net)
- **Required by**: GitHub Actions workflows in home-lab-inventory repository

### Labels and Workflow Targeting
- **Labels**: self-hosted,linux,x64,dockermaster,docker
- **Workflow targeting**: Use `runs-on: [self-hosted, dockermaster]` in workflows

## 🔗 Related Links

- [GitHub Actions Runner Documentation](https://docs.github.com/en/actions/hosting-your-own-runners)
- [Docker Image Repository](https://hub.docker.com/r/myoung34/github-runner)
- [Home Lab Inventory Repository](https://github.com/luiscamaral/home-lab-inventory)
- [GitHub Actions Workflows](https://github.com/luiscamaral/home-lab-inventory/actions)

## 📅 Change Log

| Date | Change | Author |
|------|---------|---------|
| 2025-08-21 | Service deployment and configuration | System |
| 2025-08-27 | Health check validation and optimization | System |
| 2025-08-28 | Initial documentation creation | Documentation Specialist A |

## 🔧 Setup Instructions

### Initial Setup
1. Generate GitHub Personal Access Token with repo scope
2. Copy `.env.example` to `.env` and configure token
3. Deploy with: `docker compose up -d`
4. Verify registration in GitHub repository settings

### Adding to Workflows
```yaml
jobs:
  deploy:
    runs-on: [self-hosted, dockermaster]
    steps:
      - name: Deploy to dockermaster
        run: |
          # Deployment commands here
          # Has access to /deployment directory (read-only)
```

---
*Template Version: 1.0*
*Last Updated: 2025-08-28*
*Service Status: Active and Healthy*