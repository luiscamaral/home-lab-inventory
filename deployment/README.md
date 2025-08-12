# CI/CD Pipeline for Home Lab Docker Infrastructure

This directory contains the complete CI/CD setup for automated building and deployment of Docker containers to your home lab infrastructure.

## 🏗️ Architecture Overview

Since your server is on a **restricted LAN without incoming internet access**, this setup uses a **pull-based deployment strategy**:

1. **GitHub Actions** builds Docker images when code changes
2. Images are pushed to **GitHub Container Registry** (ghcr.io)
3. Your server **pulls updates** periodically via:
   - **Watchtower** (automatic container updates)
   - **Cron job** (scheduled sync script)
   - **Manual triggers** (on-demand deployment)

## 📁 Directory Structure

```
deployment/
├── README.md                # This file
├── watchtower/             # Watchtower auto-update configuration
│   ├── docker-compose.yml
│   └── .env.example
└── scripts/                # Deployment scripts
    ├── github-sync.sh      # Pull-based sync script
    ├── install-sync-cron.sh # Installer for automated sync
    └── webhook-receiver.sh # Optional webhook receiver
```

## 🚀 Quick Start

### Step 1: Deploy Watchtower on Your Server

```bash
# SSH to your dockermaster server
ssh dockermaster

# Navigate to deployment directory
cd /nfs/dockermaster/docker/

# Copy Watchtower configuration
cp -r /path/to/repo/deployment/watchtower ./

# Configure Watchtower
cd watchtower
cp .env.example .env
nano .env  # Set WATCHTOWER_API_TOKEN

# Deploy Watchtower
docker compose up -d
```

### Step 2: Install GitHub Sync Script

```bash
# Copy sync scripts to server
scp deployment/scripts/*.sh dockermaster:/tmp/

# SSH to server
ssh dockermaster

# Install sync script
cd /tmp
chmod +x install-sync-cron.sh
./install-sync-cron.sh

# Choose option 1 (cron) or 2 (systemd timer)
```

### Step 3: Update Docker Compose Files

For each service with a custom Dockerfile:

```yaml
# Before (local build)
services:
  myservice:
    build: .

# After (using registry)
services:
  myservice:
    image: ghcr.io/luiscamaral/myservice:latest
    labels:
      com.centurylinklabs.watchtower.enable: "true"
```

## 🔄 Deployment Methods

### Method 1: Watchtower (Recommended)

Watchtower automatically pulls and updates containers when new images are available.

**Pros:**
- Fully automatic
- No external access needed
- Monitors specific containers via labels
- Cleans up old images

**Configuration:**
```yaml
services:
  myservice:
    image: ghcr.io/luiscamaral/myservice:latest
    labels:
      com.centurylinklabs.watchtower.enable: "true"
```

### Method 2: Cron-based Sync

The `github-sync.sh` script runs every 5 minutes to check for updates.

**Pros:**
- More control over deployment
- Can check GitHub commits
- Logs all deployment activities

**Check status:**
```bash
# View cron jobs
crontab -l

# View logs
tail -f /var/log/docker-deploy.log

# Run manually
/usr/local/bin/github-sync.sh
```

### Method 3: Manual Deployment

Trigger deployments manually when needed.

```bash
# Pull and deploy specific service
cd /nfs/dockermaster/docker/myservice
docker compose pull
docker compose up -d

# Or use the sync script
/usr/local/bin/github-sync.sh
```

## 🔐 Security Configuration

### GitHub Container Registry Authentication

For private images, configure Docker to authenticate with GitHub:

```bash
# Generate a Personal Access Token (PAT) on GitHub with:
# - read:packages
# - write:packages (if pushing from server)

# Login to registry
docker login ghcr.io -u YOUR_GITHUB_USERNAME

# Enter your PAT as the password
```

### Secrets Management

1. **Never commit secrets** to the repository
2. Use environment variables for sensitive data:

```yaml
# docker-compose.yml
environment:
  PASSWORD: ${SERVICE_PASSWORD:-default}

# .env file (not committed)
SERVICE_PASSWORD=actual-secret-password
```

3. **GitHub Secrets** for CI/CD:
   - Go to Settings → Secrets → Actions
   - Add required secrets:
     - `WEBHOOK_TOKEN` (if using webhooks)
     - `WATCHTOWER_HTTP_API_TOKEN` (if using API)

## 📊 GitHub Actions Workflows

### build-images.yml

Automatically builds and pushes Docker images when:
- Code is pushed to main branch
- Dockerfile changes are detected
- Manual trigger via GitHub UI

**Features:**
- Matrix builds for multiple services
- Automatic tagging (latest, commit SHA, branch name)
- Caching for faster builds
- Only builds services with Dockerfiles

### deploy.yml

Triggers deployment after successful builds:
- Webhook notification
- SSH deployment (requires setup)
- Watchtower trigger

## 🏷️ Image Tagging Strategy

Images are tagged with:
- `latest` - Latest build from main branch
- `main` - Main branch builds
- `pr-123` - Pull request builds
- `v1.2.3` - Semantic version tags
- `main-abc123` - Branch + commit SHA

## 🔧 Troubleshooting

### Watchtower Not Updating

1. Check Watchtower logs:
```bash
docker logs watchtower
```

2. Verify label is set:
```bash
docker inspect mycontainer | grep watchtower
```

3. Check image availability:
```bash
docker pull ghcr.io/luiscamaral/myservice:latest
```

### Sync Script Issues

1. Check script logs:
```bash
tail -f /var/log/docker-deploy.log
```

2. Run manually with debug:
```bash
bash -x /usr/local/bin/github-sync.sh
```

3. Verify GitHub API access:
```bash
curl https://api.github.com/repos/luiscamaral/home-lab-inventory/commits/main
```

### Permission Issues

```bash
# Fix script permissions
sudo chmod +x /usr/local/bin/github-sync.sh

# Fix Docker socket permissions
sudo usermod -aG docker $USER
```

## 📈 Monitoring

### View Deployment History

```bash
# Watchtower logs
docker logs watchtower --since 24h

# Sync script logs
grep "deployed" /var/log/docker-deploy.log

# Container update times
docker ps --format "table {{.Names}}\t{{.Status}}"
```

### Health Checks

Add health checks to your services:

```yaml
services:
  myservice:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

## 🚦 Best Practices

1. **Test locally first** before pushing to main
2. **Use staging labels** for gradual rollout:
   ```yaml
   labels:
     com.centurylinklabs.watchtower.enable: "false"  # Set to true when ready
   ```

3. **Monitor after deployment**:
   ```bash
   docker compose ps
   docker compose logs -f
   ```

4. **Backup before major updates**:
   ```bash
   docker compose down
   tar -czf backup-$(date +%Y%m%d).tar.gz ./
   ```

5. **Document service-specific requirements** in each service's README

## 📚 Additional Resources

- [GitHub Container Registry Docs](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Watchtower Documentation](https://containrrr.dev/watchtower/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

## 💡 Tips for Private LAN Deployment

Since your server can't receive incoming connections:

1. **Use pull-based updates** (Watchtower or cron)
2. **Consider a VPN** for management access
3. **Use GitHub's RSS feeds** for monitoring:
   ```
   https://github.com/luiscamaral/home-lab-inventory/commits/main.atom
   ```
4. **Set up email notifications** in Watchtower for deployment alerts
5. **Use Portainer** for visual management after deployment

---

*For questions or issues, check the repository issues or documentation.*