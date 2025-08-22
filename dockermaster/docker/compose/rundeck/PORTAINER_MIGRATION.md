# Rundeck Migration to Portainer Management

## Overview
This document describes the migration of Rundeck from local Docker build to Portainer-managed deployment using registry images.

## Migration Status
- **Date**: 2025-08-11
- **From**: Local build using Dockerfile
- **To**: Official rundeck/rundeck image from Docker Hub
- **Management**: Portainer with Git-based deployment

## Pre-Migration Configuration
- **Build Type**: Local Dockerfile build
- **Source**: Custom build context
- **Network**: macvlan (192.168.59.22)
- **Database**: PostgreSQL on 192.168.59.23

## Post-Migration Configuration

### Docker Image
- **Registry**: Docker Hub
- **Image**: `rundeck/rundeck:5.8.0`
- **Update Strategy**: Watchtower automatic updates (optional)

### Environment Variables
All sensitive configuration moved to `.env` file:
- `RUNDECK_DB_PASSWORD`
- `RUNDECK_STORAGE_PASSWORD`
- `RUNDECK_CONFIG_PASSWORD`

### Files Changed
1. **docker-compose.cicd.yml** - New compose file using registry image
2. **.env.example** - Template for environment variables
3. **PORTAINER_MIGRATION.md** - This documentation

## Migration Steps

### 1. Backup Current Data
```bash
# Backup Rundeck data
sudo tar -czf /nfs/backup/rundeck-data-$(date +%Y%m%d).tar.gz \
  /nfs/dockermaster/docker/rundeck/data

# Backup PostgreSQL database
docker exec postgres-rundeck pg_dump -U rundeck rundeck > \
  /nfs/backup/rundeck-db-$(date +%Y%m%d).sql
```

### 2. Stop Current Services
```bash
cd /nfs/dockermaster/docker/rundeck
docker compose down
```

### 3. Deploy with New Configuration
```bash
# Copy environment template
cp .env.example .env

# Edit .env with actual passwords
nano .env

# Deploy using new compose file
docker compose -f docker-compose.cicd.yml up -d
```

### 4. Configure in Portainer

#### Stack Deployment
1. Navigate to Portainer > Stacks
2. Click "Add Stack"
3. Name: `rundeck`
4. Build method: Git Repository
5. Repository URL: `https://github.com/luiscamaral/home-lab-inventory`
6. Repository reference: `main`
7. Compose path: `dockermaster/docker/compose/rundeck/docker-compose.cicd.yml`

#### Environment Variables
Add the following in Portainer stack environment:
- `RUNDECK_DB_PASSWORD`: [secure password]
- `RUNDECK_STORAGE_PASSWORD`: [secure password]
- `RUNDECK_CONFIG_PASSWORD`: [secure password]

#### Automatic Updates (Optional)
If using Watchtower, the service is already labeled for automatic updates:
```yaml
labels:
  com.centurylinklabs.watchtower.enable: "true"
```

## Verification Steps

### 1. Check Service Health
```bash
# Check if containers are running
docker ps | grep rundeck

# Check Rundeck logs
docker logs rundeck --tail 50

# Check PostgreSQL connectivity
docker exec postgres-rundeck pg_isready -U rundeck
```

### 2. Test Web Interface
- Navigate to: http://rundeck.d.lcamaral.com
- Login with existing credentials
- Verify all projects and jobs are intact

### 3. Test Job Execution
- Run a test job to verify Docker socket access
- Check that scheduled jobs are functioning

## Rollback Plan

If issues occur, rollback to the original configuration:

```bash
# Stop new services
docker compose -f docker-compose.cicd.yml down

# Restore original compose file
docker compose -f docker-compose.yml up -d

# If data was corrupted, restore from backup
sudo tar -xzf /nfs/backup/rundeck-data-[date].tar.gz -C /
docker exec -i postgres-rundeck psql -U rundeck rundeck < \
  /nfs/backup/rundeck-db-[date].sql
```

## Benefits of Migration

1. **No Local Builds**: Eliminates need for Dockerfile maintenance
2. **Faster Deployments**: Pull image instead of building
3. **Version Control**: Easy rollback to specific versions
4. **Automatic Updates**: Optional Watchtower integration
5. **GitOps**: Configuration tracked in Git repository
6. **Portainer Integration**: Centralized management UI

## Known Issues & Solutions

### Issue: Permission Denied on Docker Socket
**Solution**: Ensure the rundeck container runs with appropriate user/group for Docker socket access.

### Issue: Database Connection Failed
**Solution**: Verify PostgreSQL is running and network connectivity between containers.

### Issue: Plugins Not Loading
**Solution**: Check volume mount permissions for `/home/rundeck/container-plugins`.

## Maintenance

### Update Rundeck Version
1. Edit `docker-compose.cicd.yml`
2. Change image tag from `5.8.0` to desired version
3. Redeploy stack in Portainer or run:
   ```bash
   docker compose -f docker-compose.cicd.yml pull
   docker compose -f docker-compose.cicd.yml up -d
   ```

### Backup Schedule
Recommended backup frequency:
- **Database**: Daily at 2 AM
- **Data Directory**: Weekly on Sundays
- **Retention**: 30 days for daily, 90 days for weekly

## Support & Troubleshooting

### Logs Location
- Container logs: `docker logs rundeck`
- Application logs: `/nfs/dockermaster/docker/rundeck/data/logs/`

### Health Checks
- PostgreSQL: `docker exec postgres-rundeck pg_isready -U rundeck`
- Rundeck API: `curl -I http://192.168.59.22:4440/api/41/system/info`

### Common Commands
```bash
# Restart Rundeck
docker restart rundeck

# View real-time logs
docker logs -f rundeck

# Execute commands in container
docker exec -it rundeck bash

# Check resource usage
docker stats rundeck postgres-rundeck
```

## References
- [Rundeck Docker Documentation](https://docs.rundeck.com/docs/administration/install/docker.html)
- [Portainer Documentation](https://docs.portainer.io/)
- [Docker Compose Reference](https://docs.docker.com/compose/compose-file/)