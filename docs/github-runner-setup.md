# GitHub Runner Setup Guide

## Prerequisites

Before setting up the GitHub runner on dockermaster, ensure you have:

1. **Access Requirements**
   - SSH access to dockermaster server
   - GitHub account with repository access
   - Docker and Docker Compose installed on dockermaster

2. **GitHub Permissions**
   - Admin access to the repository (for runner registration)
   - Ability to create Personal Access Tokens

3. **Network Requirements**
   - Outbound HTTPS access to github.com
   - Access to Docker Hub and GitHub Container Registry

## Setup Steps

### Step 1: Generate GitHub Token

1. Go to GitHub Settings: https://github.com/settings/tokens/new
2. Create a new Personal Access Token with:
   - **Name**: `dockermaster-runner`
   - **Expiration**: 90 days (or as per your policy)
   - **Scopes**:
     - `repo` (Full control of private repositories)
     - `workflow` (Update GitHub Actions workflows)
     - `admin:repo_hook` (For webhook management)

3. Copy the token immediately (you won't see it again)

### Step 2: Connect to Dockermaster

```bash
ssh dockermaster
cd /path/to/home-lab-inventory
```

### Step 3: Configure Runner

1. Navigate to the runner directory:
   ```bash
   cd dockermaster/github-runner
   ```

2. Run the setup script:
   ```bash
   ./setup-runner.sh
   ```

3. When prompted:
   - Paste your GitHub token
   - Confirm runner name (or customize)
   - Add any additional labels if needed

### Step 4: Verify Runner Registration

1. Check runner status locally:
   ```bash
   docker compose ps
   docker compose logs -f runner
   ```

2. Verify in GitHub:
   - Go to: https://github.com/luiscamaral/home-lab-inventory/settings/actions/runners
   - You should see `dockermaster-runner` with status "Idle"

### Step 5: Test Runner

1. Create a test workflow (`.github/workflows/test-runner.yml`):
   ```yaml
   name: Test Self-hosted Runner
   on:
     workflow_dispatch:

   jobs:
     test:
       runs-on: [self-hosted, dockermaster]
       steps:
         - name: Check runner
           run: |
             echo "Running on: $(hostname)"
             echo "Runner name: ${{ runner.name }}"
             echo "Runner OS: ${{ runner.os }}"

         - name: Check Docker
           run: docker version
   ```

2. Trigger the workflow manually from GitHub Actions tab

## Configuration Options

### Environment Variables

Edit `.env` file to customize:

```bash
# Runner identification
RUNNER_NAME=dockermaster-runner
RUNNER_GROUP=default

# Labels for job matching
LABELS=self-hosted,linux,x64,dockermaster,docker

# GitHub authentication
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx

# Runner behavior
EPHEMERAL=false           # Clean environment after each job
DISABLE_AUTO_UPDATE=false # Allow automatic runner updates
```

### Resource Limits

Edit `docker-compose.yml` to adjust resources:

```yaml
deploy:
  resources:
    limits:
      cpus: '4'      # Increase for more parallel jobs
      memory: 8G     # Increase for memory-intensive builds
    reservations:
      cpus: '1'
      memory: 1G
```

### Network Configuration

The runner uses `docker-servers-net` network. To add additional networks:

```yaml
networks:
  docker-servers-net:
    external: true
  custom-network:
    external: true
```

## Maintenance

### Regular Maintenance Tasks

#### Daily
- Check runner status: `docker compose ps`
- Review recent logs: `docker compose logs --tail 100 runner`

#### Weekly
- Clean work directory: `rm -rf ./work/_work/*`
- Check for updates: `docker compose pull`
- Review resource usage: `docker stats github-runner-homelab`

#### Monthly
- Rotate GitHub token
- Review and clean cache: `du -sh ./cache/*`
- Update runner image: `docker compose down && docker compose up -d`

### Updating the Runner

1. Check for new runner version:
   ```bash
   docker compose pull
   ```

2. Stop and recreate container:
   ```bash
   docker compose down
   docker compose up -d
   ```

3. Verify runner is back online:
   ```bash
   docker compose logs -f runner
   ```

### Troubleshooting

#### Runner Not Starting

1. Check logs:
   ```bash
   docker compose logs runner
   ```

2. Common issues:
   - **Invalid token**: Regenerate token and update `.env`
   - **Network issues**: Check dockermaster can reach github.com
   - **Permission denied**: Check Docker socket permissions

#### Runner Offline in GitHub

1. Restart the runner:
   ```bash
   docker compose restart runner
   ```

2. If still offline, re-register:
   ```bash
   docker compose down
   rm -rf ./config/*
   ./setup-runner.sh
   ```

#### Job Failures

1. Check job logs in GitHub Actions
2. Check runner logs:
   ```bash
   docker compose logs --tail 200 runner
   ```
3. Verify Docker is accessible:
   ```bash
   docker compose exec runner docker version
   ```

#### High Resource Usage

1. Check current usage:
   ```bash
   docker stats github-runner-homelab
   ```

2. Clean work directory:
   ```bash
   docker compose down
   rm -rf ./work/*
   docker compose up -d
   ```

3. Adjust resource limits in `docker-compose.yml`

## Security Best Practices

### Token Security
- **Never** commit tokens to git
- Rotate tokens every 90 days
- Use minimal required scopes
- Consider using GitHub App tokens for production

### Container Security
- Keep runner image updated
- Don't run as root inside container
- Mount deployment paths read-only
- Use resource limits to prevent resource exhaustion

### Network Security
- Isolate runner in dedicated network
- Don't expose runner ports
- Use firewall rules to restrict outbound traffic
- Monitor network activity

### Workflow Security
- Review workflow changes carefully
- Don't run untrusted code on self-hosted runners
- Use `pull_request_target` carefully
- Implement workflow approval for external contributors

## Advanced Configuration

### Multiple Runners

To run multiple runners on the same host:

1. Copy runner directory:
   ```bash
   cp -r github-runner github-runner-2
   ```

2. Update `.env` with unique name:
   ```bash
   RUNNER_NAME=dockermaster-runner-2
   ```

3. Update container name in `docker-compose.yml`:
   ```yaml
   container_name: github-runner-homelab-2
   ```

4. Start second runner:
   ```bash
   cd github-runner-2
   docker compose up -d
   ```

### Custom Runner Image

Create custom image with additional tools:

```dockerfile
FROM myoung34/github-runner:latest

# Install additional tools
RUN apt-get update && apt-get install -y \
    ansible \
    terraform \
    kubectl

# Add custom scripts
COPY scripts/ /usr/local/bin/
```

### Monitoring Integration

Add Prometheus metrics:

```yaml
services:
  runner:
    labels:
      - prometheus.io/scrape=true
      - prometheus.io/port=9090
      - prometheus.io/path=/metrics
```

## Backup and Recovery

### Backup Strategy

What to backup:
- `.env` file (contains token)
- `config/` directory (runner registration)
- Custom scripts and configurations

Backup script:
```bash
#!/bin/bash
BACKUP_DIR="/backup/github-runner-$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"
cp .env "$BACKUP_DIR/"
cp -r config "$BACKUP_DIR/"
tar czf "$BACKUP_DIR.tar.gz" "$BACKUP_DIR"
```

### Recovery Process

1. Restore from backup:
   ```bash
   tar xzf /backup/github-runner-20240101.tar.gz
   cp github-runner-20240101/.env .
   cp -r github-runner-20240101/config .
   ```

2. Start runner:
   ```bash
   docker compose up -d
   ```

3. Verify registration:
   ```bash
   docker compose logs runner
   ```

## Support and Resources

### Getting Help
- GitHub Actions Documentation: https://docs.github.com/actions
- Runner Troubleshooting: https://docs.github.com/en/actions/hosting-your-own-runners/troubleshooting
- Repository Issues: https://github.com/luiscamaral/home-lab-inventory/issues

### Monitoring Endpoints
- Runner Status: GitHub Settings → Actions → Runners
- Workflow Runs: GitHub Actions tab
- Container Logs: `docker compose logs -f runner`

### Useful Commands
```bash
# Check runner status
docker compose ps

# View live logs
docker compose logs -f runner

# Restart runner
docker compose restart runner

# Stop runner gracefully
docker compose stop runner

# Remove runner completely
docker compose down -v
```
