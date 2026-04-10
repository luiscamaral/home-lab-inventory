# Dockermaster Service Templates

This directory contains templates for creating new services in the dockermaster environment.

## 📋 Available Templates

### 1. Service Documentation Template
- **File**: `service-documentation.md`
- **Purpose**: Complete documentation template for each service
- **Usage**: Copy and customize for each new service

### 2. Docker Compose Template
- **File**: `docker-compose.yml`
- **Purpose**: Standard Docker Compose configuration
- **Features**:
  - Macvlan network configuration
  - Volume management
  - Health checks
  - Resource limits

### 3. Environment Template
- **File**: `env-template`
- **Purpose**: Environment variable template
- **Usage**: Copy to `.env` and configure with actual values

## 🚀 Quick Start

### Creating a New Service

1. **Choose a service name**: `my-service`

2. **Create service directory**:
   ```bash
   mkdir -p dockermaster/docker/compose/my-service
   cd dockermaster/docker/compose/my-service
   ```

3. **Copy templates**:
   ```bash
   cp ../../templates/docker-compose.yml .
   cp ../../templates/env-template .env
   cp ../../templates/service-documentation.md README.md
   ```

4. **Customize the templates**:
   - Replace all `[PLACEHOLDER]` values
   - Configure IP address (next available in 192.168.59.x range)
   - Set up volumes in `/nfs/dockermaster/volumes/my-service.*`
   - Update documentation with service-specific details

5. **Test the configuration**:
   ```bash
   docker compose config
   docker compose up -d
   ```

## 🌐 Network Configuration

### IP Address Assignment
- **Network**: docker-servers-net (192.168.59.0/26)
- **Range**: 192.168.59.3 - 192.168.59.62
- **Gateway**: 192.168.48.1
- **Reserved**:
  - 192.168.59.1: host
  - 192.168.59.2: portainer

### Current Assignments
Check the main inventory for current IP assignments to avoid conflicts.

## 💾 Volume Management

### Standard Volume Locations
- **Data**: `/nfs/dockermaster/volumes/[service-name].data`
- **Config**: `/nfs/dockermaster/volumes/[service-name].config`  
- **Logs**: `/nfs/dockermaster/volumes/[service-name].logs`

### Volume Creation
```bash
sudo mkdir -p /nfs/dockermaster/volumes/[service-name].{data,config,logs}
sudo chown -R 1000:1000 /nfs/dockermaster/volumes/[service-name].*
```

## 🔐 Security Best Practices

### Environment Variables
- Store sensitive data in Vault: `http://vault.d.lcamaral.com`
- Use `.env` files for local development only
- Never commit `.env` files to git

### Vault Integration
```bash
# Store secret
vault kv put secret/dockermaster/my-service password=secret123

# Retrieve secret (in scripts)
PASSWORD=$(vault kv get -field=password secret/dockermaster/my-service)
```

### Network Security
- Services communicate through docker-servers-net
- External access through nginx reverse proxy
- Internal services should not expose ports to host

## 📊 Monitoring Standards

### Health Checks
- All services should implement health check endpoints
- Use `/health` or `/healthz` convention
- Include dependency checks (database, external APIs)

### Logging
- Use structured logging (JSON format preferred)
- Log to stdout/stderr for container logs
- Set appropriate log levels

### Metrics
- Expose Prometheus metrics on `/metrics` if supported
- Use standard metric names and labels
- Create Grafana dashboards for visualization

## 🔄 Deployment Workflow

### GitOps with GitHub Actions
1. **Development**: Test locally with templates
2. **Commit**: Push changes to git repository
3. **Deploy**: GitHub Actions deploys to dockermaster
4. **Monitor**: Check service health and logs

### Manual Deployment
```bash
# On dockermaster server
cd /nfs/dockermaster/docker/my-service
docker compose pull
docker compose up -d
```

## 📝 Maintenance

### Regular Tasks
- **Updates**: Check for image updates monthly
- **Backups**: Ensure volume backups are working
- **Monitoring**: Review dashboards and alerts
- **Documentation**: Keep service docs up to date

### Troubleshooting
- Check container logs: `docker compose logs [service]`
- Verify network connectivity: `docker exec [container] ping [target]`
- Validate configuration: `docker compose config`
- Check resource usage: `docker stats`

## 🔗 Related Documentation

- [Main Dockermaster Documentation](../README.md)
- [Network Configuration](../network/README.md)
- [Storage Configuration](../storage/README.md)
- [Service Inventory](../../inventory/docker-containers.md)

---
*Last Updated: 2025-08-28*
*Template Version: 1.0*
