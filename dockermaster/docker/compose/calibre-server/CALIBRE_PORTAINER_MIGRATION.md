# Calibre to Portainer Migration Documentation

**Migration Date**: 2025-08-21  
**Service**: Calibre Library Server  
**Target Environment**: Portainer Stack Management  
**Repository**: <https://github.com/luiscamaral/home-lab-inventory>  

## 📋 Migration Overview

### Objectives

- Migrate Calibre library server from direct Docker-compose management to Portainer stack
- Centralize container management through Portainer UI
- Improve deployment automation and monitoring capabilities
- Maintain service availability and data integrity

### Benefits

- ✅ Centralized container management through web UI
- ✅ Easier updates and rollbacks
- ✅ Better monitoring and logging
- ✅ Git-based deployment automation
- ✅ Environment variable management through UI

### Current Service Details

- **Ports**: 58080 (web UI), 58083 (content server)
- **Data Volume**: `/data/docker-volumes/calibre-library:/opt/calibre/library`
- **Configuration Volume**: `/data/docker-volumes/calibre-config:/opt/calibre/config`
- **Service Name**: calibre-library

## 🔍 Pre-migration Checklist

### Environment Verification

- [ ] Verify Portainer access at <http://192.168.59.2:9000>
- [ ] Confirm Git repository access: <https://github.com/luiscamaral/home-lab-inventory>
- [ ] Verify current service status: `docker compose ps`
- [ ] Document current resource usage: `docker stats calibre-library`
- [ ] Test network connectivity to service ports (58080, 58083)

### Backup Procedures

- [ ] **Stop current Calibre services**:

  ```bash
  cd /Users/lamaral/Library/CloudStorage/SynologyDrive-lamaral/SynDrive/05.Code/Dev/lamaral/home/inventory/dockermaster/docker/compose/calibre-server
  docker compose down
  ```

- [ ] **Backup data volumes**:

  ```bash
  # Create backup directory
  sudo mkdir -p /backup/calibre-migration-$(date +%Y%m%d)

  # Backup library data
  sudo cp -r /data/docker-volumes/calibre-library /backup/calibre-migration-$(date +%Y%m%d)/

  # Backup configuration
  sudo cp -r /data/docker-volumes/calibre-config /backup/calibre-migration-$(date +%Y%m%d)/
  ```

- [ ] **Backup current Docker-compose configuration**:

  ```bash
  cp docker-compose.yml docker-compose.yml.backup.$(date +%Y%m%d)
  cp docker-compose.portainer.yml docker-compose.portainer.yml.backup.$(date +%Y%m%d)
  ```

## 🚀 Step-by-step Migration Process

### Step 1: Access Portainer

1. Navigate to Portainer UI: **<http://192.168.59.2:9000>**
2. Log in with your credentials
3. Select the appropriate environment (usually 'local' or 'dockermaster')

### Step 2: Create New Stack

1. Go to **Stacks** in the left sidebar
2. Click **"Add stack"** button
3. Configure stack settings:
   - **Name**: `calibre-library`
   - **Build method**: Select **"Git Repository"**

### Step 3: Git Repository Configuration

Configure the following settings:

- **Repository URL**: `https://github.com/luiscamaral/home-lab-inventory`
- **Repository reference**: `main`
- **Compose path**: `dockermaster/docker/compose/calibre-server/docker-compose.portainer.yml`
- **Authentication**: None (public repository)

### Step 4: Environment Variables Setup

Add the following environment variables in Portainer:

| Variable Name | Value | Description |
|---------------|-------|-------------|
| `CALIBRE_LIBRARY_PATH` | `/opt/calibre/library` | Internal library path |
| `CALIBRE_CONFIG_PATH` | `/opt/calibre/config` | Internal config path |
| `CALIBRE_WEB_PORT` | `58080` | Web UI port |
| `CALIBRE_SERVER_PORT` | `58083` | Content server port |
| `TZ` | `America/New_York` | Timezone setting |

### Step 5: Advanced Configuration (Optional)

- **Auto-update**: Enable if desired for automatic deployments
- **Webhook**: Configure for CI/CD integration if needed
- **Access control**: Set appropriate permissions

### Step 6: Deploy Stack

1. Review configuration settings
2. Click **"Deploy the stack"** button
3. Monitor deployment progress in the logs
4. Verify stack appears in **Stacks** list with **"active"** status

## 🔧 Environment Variables Setup in Portainer

### Required Variables

Configure these environment variables in the Portainer stack:

```yaml
# Core service configuration
CALIBRE_LIBRARY_PATH=/opt/calibre/library
CALIBRE_CONFIG_PATH=/opt/calibre/config
TZ=America/New_York

# Port configuration
CALIBRE_WEB_PORT=58080
CALIBRE_SERVER_PORT=58083

# Optional: Resource limits
CALIBRE_MEMORY_LIMIT=1024M
CALIBRE_CPU_LIMIT=1.0
```

### Setting Variables in Portainer UI

1. In stack configuration, scroll to **"Environment variables"** section
2. Add variables using key-value pairs:
   - **name**: Variable name (e.g., `TZ`)
   - **value**: Variable value (e.g., `America/New_York`)
3. Alternatively, use **"Advanced mode"** for bulk variable entry

## 🔄 Rollback Procedures

### Emergency Rollback

If issues occur during migration:

1. **Stop Portainer stack**:
   - Go to Stacks → calibre-library → Stop

2. **Restore original Docker-compose service**:

   ```bash
   cd /Users/lamaral/Library/CloudStorage/SynologyDrive-lamaral/SynDrive/05.Code/Dev/lamaral/home/inventory/dockermaster/docker/compose/calibre-server
   docker compose up -d
   ```

3. **Verify service restoration**:

   ```bash
   docker compose ps
   curl http://192.168.59.2:58080
   ```

### Data Restoration (if needed)

1. **Stop all services**:

   ```bash
   docker compose down
   # OR in Portainer: Stop stack
   ```

2. **Restore from backup**:

   ```bash
   # Restore library data
   sudo rm -rf /data/docker-volumes/calibre-library
   sudo cp -r /backup/calibre-migration-$(date +%Y%m%d)/calibre-library /data/docker-volumes/

   # Restore configuration
   sudo rm -rf /data/docker-volumes/calibre-config
   sudo cp -r /backup/calibre-migration-$(date +%Y%m%d)/calibre-config /data/docker-volumes/
   ```

3. **Restart services**:

   ```bash
   docker compose up -d
   ```

## 🔧 Troubleshooting Guide

### Common Issues

#### Issue 1: Stack Deployment Fails

**Symptoms**: Stack shows "failed" status
**Solutions**:

- Check Git repository accessibility
- Verify Docker-compose.portainer.yml syntax
- Review environment variables for typos
- Check Portainer logs: Stacks → calibre-library → Editor → View logs

#### Issue 2: Services Not Starting

**Symptoms**: Containers in "exited" state
**Solutions**:

- Verify volume paths exist: `/data/docker-volumes/calibre-*`
- Check port availability: `netstat -tulpn | grep :58080`
- Review container logs in Portainer: Containers → calibre-library → Logs
- Verify resource limits and availability

#### Issue 3: Web UI Not Accessible

**Symptoms**: Cannot access <http://192.168.59.2:58080>
**Solutions**:

- Confirm container is running: Check in Portainer Containers view
- Verify port mapping: Should show `0.0.0.0:58080->8080/tcp`
- Check firewall rules on dockermaster
- Test internal connectivity: `docker exec -it calibre-library wget -q --spider http://localhost:8080`

#### Issue 4: Library Not Loading

**Symptoms**: Calibre web shows empty library
**Solutions**:

- Verify volume mount: `/data/docker-volumes/calibre-library` → `/opt/calibre/library`
- Check file permissions: `sudo ls -la /data/docker-volumes/calibre-library`
- Ensure metadata.db exists in library path
- Review container environment variables

### Log Locations

- **Portainer Stack Logs**: Stacks → calibre-library → Editor → View logs
- **Container Logs**: Containers → calibre-library → Logs
- **System Logs**: SSH to dockermaster, `journalctl -u docker`

### Network Troubleshooting

```bash
# Test port connectivity
telnet 192.168.59.2 58080
telnet 192.168.59.2 58083

# Check container network
docker network ls
docker network inspect bridge

# Verify DNS resolution
nslookup 192.168.59.2
```

## ✅ Post-migration Validation

### Service Accessibility Tests

- [ ] **Web UI Access**: Navigate to <http://192.168.59.2:58080>
- [ ] **Content Server**: Test <http://192.168.59.2:58083>
- [ ] **Library Loading**: Verify books appear in web interface
- [ ] **Search Functionality**: Test book search and filtering
- [ ] **Download Test**: Try downloading a sample book

### Data Integrity Verification

```bash
# Check volume mounts
docker inspect calibre-library | grep Mounts -A 20

# Verify data directory contents
sudo ls -la /data/docker-volumes/calibre-library/
sudo ls -la /data/docker-volumes/calibre-config/

# Check database integrity
sudo file /data/docker-volumes/calibre-library/metadata.db
```

### Performance Baseline

- [ ] **Memory Usage**: Record baseline memory consumption
- [ ] **CPU Usage**: Monitor during normal operations
- [ ] **Response Time**: Time web UI page loads
- [ ] **Book Upload**: Test library management functions

### Monitoring Setup

- [ ] **Portainer Monitoring**: Enable container statistics
- [ ] **Log Aggregation**: Configure log retention settings
- [ ] **Health Checks**: Verify service health endpoints
- [ ] **Alerts**: Configure failure notifications if available

## 📊 Success Criteria

### Migration Complete When

- ✅ Portainer stack deployed and running
- ✅ All services accessible via original URLs
- ✅ Library data intact and searchable
- ✅ Configuration preserved
- ✅ Performance meets or exceeds baseline
- ✅ Monitoring and logging functional
- ✅ Rollback procedure tested and documented

### Post-Migration Tasks

1. **Update documentation**: Record any configuration changes
2. **Monitor stability**: Observe for 24-48 hours
3. **Performance optimization**: Adjust resource limits if needed
4. **Backup validation**: Verify backup procedures work with new setup
5. **Team notification**: Inform stakeholders of migration completion

## 📝 Notes and Lessons Learned

### Migration Date: ___________

### Performed by: ___________

### Duration: ___________

**Issues Encountered:**

- [ ] None
- [ ] _________________________
- [ ] _________________________

**Performance Changes:**

- Memory usage: Before _____ / After _____
- CPU usage: Before _____ / After _____
- Response time: Before _____ / After _____

**Recommendations for Future Migrations:**

- _________________________
- _________________________
- _________________________

---
**Document Version**: 1.0  
**Last Updated**: 2025-08-21  
**Next Review**: 2025-09-21
