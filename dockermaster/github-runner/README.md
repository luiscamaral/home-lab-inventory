# GitHub Actions Runner for Home Lab

This directory contains the configuration for a self-hosted GitHub Actions runner running on dockermaster.

## 🚀 Quick Start

### 1. Prerequisites
- Docker and Docker Compose installed on dockermaster
- GitHub Personal Access Token with `repo` scope
- Access to the dockermaster server

### 2. Configuration

1. Copy the environment template:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` and add your GitHub token:
   ```bash
   GITHUB_TOKEN=your_personal_access_token_here
   ```

3. Start the runner:
   ```bash
   docker compose up -d
   ```

### 3. Verify Runner Registration

1. Go to your repository settings: https://github.com/luiscamaral/home-lab-inventory/settings/actions/runners
2. You should see `dockermaster-runner` in the list of runners
3. The runner should show as "Idle" when ready

## 📋 Configuration Options

### Runner Labels
The runner is configured with the following labels:
- `self-hosted` - Identifies as self-hosted runner
- `linux` - Linux operating system
- `x64` - 64-bit architecture
- `dockermaster` - Specific to this server
- `docker` - Has Docker capabilities

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `RUNNER_NAME` | Name of the runner | `dockermaster-runner` |
| `RUNNER_GROUP` | Runner group | `default` |
| `LABELS` | Comma-separated labels | `self-hosted,linux,x64,dockermaster,docker` |
| `GITHUB_TOKEN` | GitHub PAT or App token | (required) |
| `EPHEMERAL` | Clean environment each run | `false` |
| `DISABLE_AUTO_UPDATE` | Prevent auto-updates | `false` |

## 🔧 Maintenance

### Viewing Logs
```bash
docker compose logs -f runner
```

### Stopping the Runner
```bash
docker compose down
```

### Updating the Runner
```bash
docker compose pull
docker compose up -d
```

### Cleaning Work Directory
```bash
# Stop the runner first
docker compose down

# Clean work directory
rm -rf ./work/*

# Restart
docker compose up -d
```

## 🔒 Security Considerations

1. **Token Security**: Never commit the `.env` file with tokens
2. **Volume Mounts**: Deployment paths are mounted read-only
3. **Resource Limits**: CPU and memory limits are configured
4. **Network Isolation**: Uses the docker-servers-net network
5. **No Auto-updates**: Watchtower is disabled for stability

## 📁 Directory Structure

```
github-runner/
├── docker-compose.yml    # Runner container configuration
├── .env.example          # Environment template
├── .env                  # Actual configuration (git-ignored)
├── README.md            # This file
├── work/                # Runner work directory (auto-created)
├── cache/               # Build cache (auto-created)
└── config/              # Runner configuration (auto-created)
```

## 🚨 Troubleshooting

### Runner Not Appearing in GitHub
1. Check the logs: `docker compose logs runner`
2. Verify the token has `repo` scope
3. Ensure the repository URL is correct

### Runner Shows Offline
1. Check container status: `docker compose ps`
2. Verify network connectivity
3. Check Docker socket permissions

### Permission Errors
1. Ensure Docker socket is accessible
2. Check volume mount permissions
3. Verify the container user has necessary permissions

### High Resource Usage
1. Adjust resource limits in docker-compose.yml
2. Enable ephemeral mode for cleaner environments
3. Regularly clean the work directory

## 📊 Monitoring

The runner includes a health check that verifies the Runner.Listener process is running. You can check the health status with:

```bash
docker inspect github-runner-homelab --format='{{.State.Health.Status}}'
```

## 🔄 Workflow Usage

To use this runner in your workflows, specify:

```yaml
jobs:
  build:
    runs-on: [self-hosted, dockermaster]
    # or for fallback to GitHub runners:
    runs-on: [self-hosted, dockermaster] || ubuntu-latest
```

## 📝 Notes

- The runner is configured to persist between jobs (not ephemeral)
- Auto-updates are enabled by default for security
- The runner has access to Docker for building images
- Deployment paths are mounted read-only for safety
