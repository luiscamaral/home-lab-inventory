# Ansible Stack Service Documentation

## 📊 Service Overview

- **Service Name**: Ansible-stack
- **Category**: Infrastructure Management / Network Documentation
- **Status**: Configured (NetBox-based)
- **IP Address**: Not explicitly configured (using default network)
- **External URL**: Not configured

## 🚀 Description

The Ansible-stack service is a NetBox-based infrastructure documentation and automation platform. NetBox is a web
application designed to help manage and document computer networks, originally designed by DigitalOcean. This service
appears to be set up for network documentation and infrastructure management tasks.

## 🔧 Configuration

### Docker Compose Location

```text
/nfs/dockermaster/docker/ansible-stack/netbox/docker-compose.yml
```

### Service Architecture

The stack consists of multiple interconnected services:

- **netbox**: Main NetBox application
- **netbox-worker**: Background task processor
- **netbox-housekeeping**: Maintenance tasks
- **postgres**: Database backend
- **Redis**: Primary cache and task queue
- **Redis-cache**: Secondary cache

### Environment Variables

- **Database Configuration**:
  - `DB_HOST`: Ansible-stack-netbox-postgres
  - `DB_NAME`: netbox
  - `DB_USER`: netbox
  - `DB_PASSWORD`: [Configured]

- **Redis Configuration**:
  - `REDIS_HOST`: Ansible-stack-netbox-Redis
  - `REDIS_CACHE_HOST`: Ansible-stack-netbox-Redis-cache
  - `REDIS_DATABASE`: 0
  - `REDIS_CACHE_DATABASE`: 1

- **Application Settings**:
  - `CORS_ORIGIN_ALLOW_ALL`: True
  - `GRAPHQL_ENABLED`: true
  - `WEBHOOKS_ENABLED`: true
  - `METRICS_ENABLED`: false

### Volumes

- `netbox-media-files`: Media file storage
- `netbox-postgres-data`: Database data
- `netbox-redis-data`: Redis primary data
- `netbox-redis-cache-data`: Redis cache data
- `netbox-reports-files`: Reports storage
- `netbox-scripts-files`: Custom scripts storage

### Network Configuration

- **Network**: Default Docker network (not explicitly configured)
- **Ports**: Not explicitly exposed (internal services only)

## 🔐 Security

### Secrets Management

- Database passwords stored in environment files
- Redis passwords configured for both instances
- Secret key configured for application security

### Access Control

- Authentication method: NetBox built-in authentication
- Superuser creation skipped (`SKIP_SUPERUSER=true`)

## 📈 Monitoring

### Health Checks

- **NetBox**: HTTP health check on localhost:8080/login/
  - Interval: 15s
  - Timeout: 3s
  - Start period: 90s
- **Worker**: Process-based health check (rqworker)
- **Housekeeping**: Process-based health check
- **Postgres**: pg_isready check
- **Redis**: PING command check

### Metrics

- **Prometheus**: Disabled (`METRICS_ENABLED=false`)
- **Application monitoring**: Available through NetBox interface

## 🔄 Backup Strategy

### Data Backup

- **Database**: Volume-based backup (netbox-postgres-data)
- **Media Files**: Volume-based backup (netbox-media-files)
- **Redis Data**: Volume-based backup for both Redis instances

### Configuration Backup

- **Git repository**: Yes - included in dockermaster repo
- **Environment files**: Stored in env/ directory

## 🚨 Troubleshooting

### Common Issues

1. **Issue**: NetBox fails to start
   - **Symptoms**: Health check failures
   - **Solution**: Check database connectivity and Redis availability

2. **Issue**: Worker processes not running
   - **Symptoms**: Background tasks not processing
   - **Solution**: Check worker container logs and Redis connection

### Log Locations

- **Container logs**:
  - `docker logs ansible-stack-netbox`
  - `docker logs ansible-stack-netbox-worker`
  - `docker logs ansible-stack-netbox-housekeeping`
  - `docker logs ansible-stack-netbox-postgres`
  - `docker logs ansible-stack-netbox-redis`

### Recovery Procedures

1. **Service restart**: `docker compose restart <service>`
2. **Full rebuild**: `docker compose down && docker compose up -d`
3. **Database recovery**: Restore from netbox-postgres-data volume backup

## 📝 Maintenance

### Updates

- **Update schedule**: Manual (version controlled via environment variable)
- **Current version**: v4.2-3.2.0 (NetBox)
- **Update procedure**: Update VERSION environment variable and recreate containers

### Dependencies

- **Required services**: postgres, Redis, Redis-cache
- **Required by**: Infrastructure documentation workflows
- **Service order**: postgres/Redis → netbox → worker/housekeeping

### Environment Files Structure

```text
env/
├── netbox.env          # Main NetBox configuration
├── postgres.env        # Database settings
├── redis.env           # Primary Redis settings
└── redis-cache.env     # Cache Redis settings
```

## 🔗 Related Links

- [NetBox Official Documentation](https://docs.netbox.dev/)
- [NetBox Community Docker](https://github.com/netbox-community/netbox-docker)
- [NetBox Docker Hub](https://hub.docker.com/r/netboxcommunity/netbox)
- [Ansible Integration](https://docs.netbox.dev/en/stable/integrations/ansible/)

## 📅 Change Log

| Date | Change | Author |
|------|---------|---------|
| 2025-08-28 | Initial documentation | Documentation Team |

---
_Template Version: 1.0_
_Last Updated: 2025-08-28_
