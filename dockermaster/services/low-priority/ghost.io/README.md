# Ghost.io Service Documentation

## 📊 Service Overview

- **Service Name**: ghost.io
- **Category**: Blog Platform / CMS
- **Status**: Active
- **IP Address**: Host network (port 6368)
- **External URL**: http://dockermaster.srv.lcamaral.com:6368

## 🚀 Description

Ghost is a modern, open source publishing platform built on Node.js. This service provides a powerful blogging platform with a clean, minimalist interface for content creation and management. It's designed for professional publishing with built-in SEO, social sharing, and membership features.

## 🔧 Configuration

### Docker Compose Location
```
/nfs/dockermaster/docker/ghost.io/docker-compose.yaml
```

### Service Architecture
The stack consists of two services:
- **ghost**: Main Ghost application (Ghost 5 Alpine)
- **db**: MySQL 8.0 database backend

### Environment Variables
- **Database Configuration**:
  - `database__client`: mysql
  - `database__connection__host`: db
  - `database__connection__user`: root
  - `database__connection__password`: example
  - `database__connection__database`: ghost

- **Application Settings**:
  - `url`: http://dockermaster.srv.lcamaral.com:6368
  - `NODE_ENV`: production (default)

### Volumes
- `ghost`: Content storage using bind mount to `/nfs/dockermaster/ghost.io/volumes/ghost`
- `db`: Database storage using bind mount to `/nfs/dockermaster/ghost.io/volumes/db`

### Network Configuration
- **Network**: Default Docker bridge network
- **Ports**:
  - External: 6368 (mapped from internal 2368)
  - Internal: Ghost app on port 2368, MySQL on port 3306

## 🔐 Security

### Secrets Management
- Database root password: `example` (should be changed for production)
- No advanced authentication configured

### Access Control
- **Authentication method**: Ghost built-in user management
- **Admin access**: Through Ghost web interface
- **Database access**: Internal container communication only

## 📈 Monitoring

### Health Checks
- **Current**: None explicitly configured
- **Application monitoring**: Available through Ghost admin interface
- **Database**: No health checks configured

### Metrics
- **Prometheus**: Not configured
- **Application analytics**: Available through Ghost admin panel

## 🔄 Backup Strategy

### Data Backup
- **Ghost content**: Bind mount to `/nfs/dockermaster/ghost.io/volumes/ghost`
- **Database**: Bind mount to `/nfs/dockermaster/ghost.io/volumes/db`
- **Method**: File system backup of mounted volumes

### Configuration Backup
- **Git repository**: Yes - docker-compose.yaml included in dockermaster repo
- **Ghost config**: Stored in content volume

## 🚨 Troubleshooting

### Common Issues
1. **Issue**: Ghost fails to connect to database
   - **Symptoms**: Container restart loops, database connection errors
   - **Solution**: Check MySQL container status and credentials

2. **Issue**: Theme or content missing
   - **Symptoms**: Site appears broken or default
   - **Solution**: Check Ghost content volume mount and permissions

3. **Issue**: External access not working
   - **Symptoms**: Site not accessible from external network
   - **Solution**: Verify URL configuration and port forwarding

### Log Locations
- **Container logs**:
  - `docker logs <ghost-container-name>`
  - `docker logs <mysql-container-name>`
- **Application logs**: Available in Ghost content volume

### Recovery Procedures
1. **Service restart**: `docker compose restart`
2. **Full rebuild**: `docker compose down && docker compose up -d`
3. **Content recovery**: Restore from `/nfs/dockermaster/ghost.io/volumes/ghost` backup
4. **Database recovery**: Restore from `/nfs/dockermaster/ghost.io/volumes/db` backup

## 📝 Maintenance

### Updates
- **Current version**: Ghost 5 (Alpine)
- **MySQL version**: 8.0
- **Update schedule**: Manual updates recommended
- **Update procedure**:
  1. Backup content and database volumes
  2. Update image tags in compose file
  3. Recreate containers
  4. Verify functionality

### Dependencies
- **Required services**: MySQL database
- **Service startup order**: db → ghost
- **External dependencies**: None

### Volume Management
- **Content location**: `/nfs/dockermaster/ghost.io/volumes/ghost`
- **Database location**: `/nfs/dockermaster/ghost.io/volumes/db`
- **Mount type**: Bind mounts (not Docker volumes)

## 🔧 Features

### Publishing Features
- **Content editor**: Modern block-based editor
- **Themes**: Customizable themes and layouts
- **SEO**: Built-in SEO optimization
- **Social sharing**: Social media integration
- **Comments**: Built-in commenting system

### Technical Features
- **Performance**: Built on Node.js for speed
- **API**: RESTful API for integrations
- **Webhooks**: Support for external integrations
- **Custom code**: HTML/CSS/JavaScript injection

### Admin Features
- **User management**: Multi-user support with roles
- **Analytics**: Basic traffic and engagement metrics
- **Import/Export**: Content migration tools

## 🔗 Related Links

- [Ghost Official Documentation](https://ghost.org/docs/)
- [Ghost Docker Hub](https://hub.docker.com/_/ghost)
- [Ghost API Documentation](https://ghost.org/docs/content-api/)
- [Ghost Themes](https://ghost.org/marketplace/)

## 📅 Change Log

| Date | Change | Author |
|------|---------|---------|
| 2025-08-28 | Initial documentation | Documentation Team |

---
*Template Version: 1.0*
*Last Updated: 2025-08-28*
