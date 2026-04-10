# Calibre Server Monitoring Setup
<!-- Agent F: Monitoring Specialist - LCMA 2025 -->
<!-- Purpose: Complete monitoring implementation guide for Portainer-managed Calibre -->

## 📊 Overview

Complete monitoring configuration for Calibre services migrated to Portainer, including health checks, resource monitoring, auto-updates, and alerting.

## 🔧 Portainer Alert Configuration Steps

### 1. Enable Monitoring in Portainer

```bash
# Access Portainer dashboard
# Navigate to: Settings > Notifications

# Configure notification providers:
# 1. Webhook notifications for alerts
# 2. Email notifications for critical issues
# 3. Slack/Discord integration (optional)
```

### 2. Create Health Check Endpoints

```yaml
# Add to docker-compose.yml
services:
  calibre:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  calibre-web:
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8083/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
```

### 3. Configure Portainer Webhooks

```bash
# In Portainer UI:
# 1. Go to Stacks > calibre-server
# 2. Enable "Auto-update"
# 3. Set webhook URL from GitHub
# 4. Configure pull interval: 24h
```

## 📈 Resource Usage Baselines

### Normal Operating Parameters

| Service | Memory | CPU | Network I/O | Disk I/O |
|---------|--------|-----|-------------|-----------|
| Calibre Server | 200-500MB | 5-20% | Low (idle) | Medium (operations) |
| Calibre-Web | 100-300MB | 2-15% | Low-Medium | Low |

### Performance Indicators

#### 🟢 Healthy State
- **Startup Time**: < 60s for Calibre, < 30s for Calibre-Web
- **Response Time**: < 2s for web interface
- **Memory Growth**: Stable, no continuous increase
- **CPU**: Spikes during book processing, idle < 20%

#### 🟡 Warning Indicators
- **Memory**: > 80% of allocated resources
- **CPU**: > 85% sustained for 5+ minutes  
- **Response Time**: > 5s consistently
- **Disk Space**: > 80% of volume capacity

#### 🔴 Critical Issues
- **Container Down**: > 2 minutes unresponsive
- **Memory**: > 95% allocation
- **Disk Space**: > 90% volume capacity
- **Failed Health Checks**: 3+ consecutive failures

## 🔗 GitHub Webhook Setup for Auto-Deploy

### 1. Create Webhook in GitHub Repository

```bash
# Repository Settings > Webhooks > Add webhook
# Payload URL: https://your-portainer-url:9443/api/webhooks/{webhook-token}
# Content type: application/json
# Events: Push events (main branch)
```

### 2. Configure Auto-Deploy Script

```yaml
# .github/workflows/deploy-calibre.yml
name: Deploy to Portainer
on:
  push:
    branches: [main]
    paths:
      - 'dockermaster/docker/compose/calibre-server/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Trigger Portainer Update
        run: |
          curl -X POST "${{ secrets.PORTAINER_WEBHOOK_URL }}"
```

### 3. Environment Variables

```bash
# Set in GitHub Secrets:
PORTAINER_WEBHOOK_URL=https://portainer.local:9443/api/webhooks/xxxxx
GITHUB_WEBHOOK_SECRET=your-secret-key
```

## 📊 Monitoring Dashboard Recommendations

### Portainer Built-in Monitoring

1. **Container Overview**
   - Service status indicators
   - Resource usage graphs
   - Health check status
   - Recent logs access

2. **Resource Monitoring**
   - CPU/Memory usage over time
   - Network I/O statistics
   - Volume usage tracking
   - Container restart history

### External Monitoring Integration

#### Option 1: Prometheus + Grafana (Recommended)

```yaml
# Add to docker-compose.yml
prometheus:
  image: prom/prometheus:latest
  volumes:
    - ./prometheus.yml:/etc/prometheus/prometheus.yml
    - prometheus_data:/prometheus

grafana:
  image: grafana/grafana:latest
  environment:
    - GF_SECURITY_ADMIN_PASSWORD=secure_password
  volumes:
    - grafana_data:/var/lib/grafana
```

#### Option 2: Simple Uptime Monitoring

```bash
# Install uptime-kuma alongside Portainer
docker run -d \
  --name uptime-kuma \
  -p 3001:3001 \
  -v uptime-kuma:/app/data \
  louislam/uptime-kuma:1
```

## 🔔 Alert Configuration

### Critical Alerts (Immediate Response)
- Container down > 2 minutes
- Volume usage > 90%
- Memory usage > 95%
- Failed database connections

### Warning Alerts (Monitor Closely)
- Memory usage > 80%
- CPU usage > 85% for 5+ minutes
- Response time > 5 seconds
- Volume usage > 80%

### Info Alerts (FYI)
- Container restarts
- Successful updates
- Weekly resource reports

## 🛠️ Implementation Checklist

### Initial Setup
- [ ] Deploy monitoring-config.yml to Portainer
- [ ] Configure watchtower with auto-update schedule
- [ ] Set up health check endpoints
- [ ] Configure notification channels

### Portainer Configuration
- [ ] Enable container monitoring
- [ ] Set up webhook endpoints
- [ ] Configure alert thresholds
- [ ] Test notification delivery

### GitHub Integration
- [ ] Create repository webhook
- [ ] Configure auto-deploy workflow
- [ ] Set environment secrets
- [ ] Test deployment pipeline

### Monitoring Validation
- [ ] Verify health checks working
- [ ] Test alert triggers
- [ ] Confirm auto-updates scheduled
- [ ] Validate dashboard access

## 🔍 Troubleshooting Guide

### Common Issues

#### Health Checks Failing
```bash
# Debug health check
docker exec calibre-server curl -f http://localhost:8080/
docker logs calibre-server --tail 50
```

#### High Memory Usage
```bash
# Check memory allocation
docker stats calibre-server
docker exec calibre-server free -h
```

#### Update Failures
```bash
# Check watchtower logs
docker logs watchtower
# Manual update test
docker pull linuxserver/calibre-web:latest
```

### Performance Optimization
1. **Memory**: Increase container memory limits if consistently high
2. **CPU**: Consider resource scheduling during peak hours
3. **Storage**: Implement log rotation and cleanup policies
4. **Network**: Monitor for unusual traffic patterns

## 📝 Maintenance Schedule

### Daily (Automated)
- Health check monitoring
- Resource usage tracking
- Log rotation
- Auto-updates (4 AM)

### Weekly (Manual Review)
- Performance metrics review
- Alert threshold evaluation
- Backup verification
- Security updates check

### Monthly (Comprehensive)
- Monitoring configuration review
- Baseline adjustment
- Performance optimization
- Documentation updates

## 🔐 Security Considerations

### Monitoring Security
- Secure webhook endpoints with authentication
- Encrypt notification channels
- Limit monitoring access permissions
- Regular monitoring credential rotation

### Container Security
- Enable security scanning in updates
- Monitor for CVE alerts
- Implement least-privilege access
- Regular security baseline reviews

---

**Last Updated**: 2025-08-21  
**Configuration Version**: 1.0  
**Agent**: F - Monitoring Specialist  
**Project**: LCMA 2025 - Calibre Portainer Migration
