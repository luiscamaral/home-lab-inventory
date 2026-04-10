# Solr Service Documentation

## 📊 Service Overview

- **Service Name**: solr
- **Category**: Search Engine / Full-Text Search
- **Status**: Active
- **IP Address**: Host network (port 8983)
- **External URL**: http://dockermaster:8983

## 🚀 Description

Apache Solr is a highly reliable, scalable, and fault-tolerant search platform that provides distributed indexing, replication, and load-balanced querying. This service provides full-text search capabilities and is likely used by other services in the infrastructure for document search and indexing features.

## 🔧 Configuration

### Docker Compose Location
```
/nfs/dockermaster/docker/solr/docker-compose.yml
```

### Service Architecture
- **solr**: Single Solr instance with pre-created core
- **Core name**: mycore (automatically created on startup)

### Environment Variables
- **No explicit environment variables configured**
- **Default Solr configuration applies**

### Volumes
- `./data`: Solr core data mounted to `/opt/solr/server/solr/mycores`

### Network Configuration
- **Network**: Default Docker bridge network
- **Ports**:
  - External: 8983 (mapped to internal 8983)
  - Web interface and API available on port 8983

## 🔐 Security

### Secrets Management
- **Current setup**: No authentication configured (default Solr installation)
- **Access control**: None configured
- **Security options**: AppArmor unconfined

### Access Control
- **Authentication**: None (open access)
- **Authorization**: Not configured
- **Network access**: Available to all Docker networks

## 📈 Monitoring

### Health Checks
- **Current**: No explicit health checks configured
- **Solr admin**: Available via web interface at http://localhost:8983/solr/
- **Core status**: Can be monitored via Solr admin interface

### Metrics
- **Solr metrics**: Available via admin interface and JMX
- **Prometheus**: Not explicitly configured
- **Custom dashboards**: Available through Solr admin UI

## 🔄 Backup Strategy

### Data Backup
- **Method**: Volume backup of ./data directory
- **Core data**: Stored in mounted data directory
- **Frequency**: Depends on volume backup schedule

### Configuration Backup
- **Git repository**: Yes - docker-compose.yml included
- **Solr configuration**: Stored in data volume with core

## 🚨 Troubleshooting

### Common Issues
1. **Issue**: Solr core not accessible
   - **Symptoms**: 404 errors when accessing core
   - **Solution**: Check if mycore was created successfully

2. **Issue**: High memory usage
   - **Symptoms**: Container using excessive memory
   - **Solution**: Check JVM settings and optimize for workload

3. **Issue**: Search performance issues
   - **Symptoms**: Slow query responses
   - **Solution**: Check index optimization and JVM heap size

### Log Locations
- **Container logs**: `docker logs <solr-container-name>`
- **Solr logs**: Available in container and via admin interface

### Recovery Procedures
1. **Service restart**: `docker compose restart solr`
2. **Full rebuild**: `docker compose down && docker compose up -d`
3. **Core recovery**: Restore from data directory backup
4. **Index rebuild**: May require reindexing from source data

## 📝 Maintenance

### Updates
- **Current version**: Latest Solr (unspecified version)
- **Update schedule**: Manual updates (Watchtower disabled)
- **Update procedure**:
  1. Backup data directory
  2. Update image tag
  3. Restart container
  4. Verify core functionality

### Dependencies
- **Required services**: None (standalone)
- **Required by**: Likely used by docspell and potentially other search-enabled services
- **Data dependencies**: Applications that index content into Solr

### Resource Limits
- **CPU Limits**: 2 cores maximum
- **Memory Limits**: 4GB maximum
- **CPU Reservations**: 0.5 cores minimum
- **Memory Reservations**: 512MB minimum

## 🔧 Features

### Solr Features
- **Full-text search**: Advanced text search capabilities
- **Faceted search**: Multi-dimensional search filtering
- **Highlighting**: Search result highlighting
- **Auto-complete**: Suggestion capabilities
- **Geospatial search**: Location-based search support

### Core Configuration
- **Pre-created core**: mycore automatically created on startup
- **Schema**: Default Solr schema (customizable)
- **Index updates**: Real-time indexing support
- **Query handlers**: Standard Solr query handlers

### Administrative Features
- **Web interface**: Complete admin interface on port 8983
- **Core management**: Create, reload, and manage cores
- **Query testing**: Built-in query testing interface
- **Performance monitoring**: Built-in statistics and monitoring

### Integration Options
- **REST API**: Full REST API for indexing and searching
- **JSON support**: Native JSON support for documents and responses
- **XML support**: Traditional XML format support
- **Client libraries**: Available for multiple programming languages

## 🔗 Related Links

- [Apache Solr Documentation](https://solr.apache.org/guide/)
- [Solr Docker Hub](https://hub.docker.com/_/solr)
- [Solr REST API](https://solr.apache.org/guide/solr/latest/indexing-guide/indexing-with-update-handlers.html)
- [Solr Admin UI](https://solr.apache.org/guide/solr/latest/deployment-guide/solr-admin-ui.html)

## 📅 Change Log

| Date | Change | Author |
|------|---------|---------|
| 2025-08-28 | Initial documentation | Documentation Team |

---
*Template Version: 1.0*
*Last Updated: 2025-08-28*
