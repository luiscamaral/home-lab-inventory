# MongoDB Service Documentation

## 📊 Service Overview

- **Service Name**: mongodb
- **Category**: NoSQL Database
- **Status**: Active
- **IP Address**: 192.168.59.41 (MongoDB), 192.168.59.40 (Mongo Express)
- **External URL**: Not configured (internal access only)

## 🚀 Description

MongoDB is a document-oriented NoSQL database that provides high performance, high availability, and easy scalability. This service includes both the MongoDB database server and Mongo Express, a web-based MongoDB admin interface for database management and monitoring.

## 🔧 Configuration

### Docker Compose Location
```
/nfs/dockermaster/docker/mongodb/docker-compose.yaml
```

### Service Architecture
The stack consists of two services:
- **mongo**: MongoDB 6.0 database server
- **mongo-express**: Web-based admin interface

### Environment Variables
- **MongoDB Configuration**:
  - `MONGO_INITDB_ROOT_USERNAME`: root
  - `MONGO_INITDB_ROOT_PASSWORD`: saturno

- **Mongo Express Configuration**:
  - `ME_CONFIG_MONGODB_ADMINUSERNAME`: root
  - `ME_CONFIG_MONGODB_ADMINPASSWORD`: saturno
  - `ME_CONFIG_MONGODB_URL`: mongodb://root:saturno@mongo:27017/

### Volumes
- `mongodb_data`: Database data storage (/data/db)
- `mongodb_config`: Database configuration storage (/data/configdb)

### Network Configuration
- **Network**: docker-servers-net (macvlan)
- **IP Addresses**:
  - MongoDB: 192.168.59.41
  - Mongo Express: 192.168.59.40
- **Ports**:
  - MongoDB: 27017 (internal)
  - Mongo Express: 8081 (currently commented out)

## 🔐 Security

### Secrets Management
- Database root credentials stored in docker-compose
- Authentication enabled with root user access

### Access Control
- **Authentication method**: MongoDB built-in authentication
- **Root user**: root / saturno
- **Admin interface**: Mongo Express with same credentials
- **Network access**: Limited to docker-servers-net

## 📈 Monitoring

### Health Checks
- **Current**: No explicit health checks configured
- **Database monitoring**: Available through Mongo Express interface
- **Connection testing**: Can be done via MongoDB clients

### Metrics
- **MongoDB metrics**: Available through MongoDB's built-in stats
- **Prometheus**: Not explicitly configured
- **Admin interface**: Mongo Express provides web-based monitoring

## 🔄 Backup Strategy

### Data Backup
- **Method**: Volume backup of mongodb_data and mongodb_config
- **Frequency**: Depends on volume backup schedule
- **Database dumps**: Can be created using mongodump command

### Configuration Backup
- **Git repository**: Yes - docker-compose.yaml included
- **Database configuration**: Stored in mongodb_config volume

## 🚨 Troubleshooting

### Common Issues
1. **Issue**: MongoDB fails to start
   - **Symptoms**: Container exits or restart loops
   - **Solution**: Check volume permissions and initialization logs

2. **Issue**: Authentication failures
   - **Symptoms**: Cannot connect to database
   - **Solution**: Verify username/password and authentication database

3. **Issue**: Mongo Express cannot connect
   - **Symptoms**: Admin interface shows connection errors
   - **Solution**: Check MongoDB service availability and credentials

### Log Locations
- **Container logs**:
  - `docker logs <mongo-container-name>`
  - `docker logs <mongo-express-container-name>`
- **MongoDB logs**: Available in container logs and data volume

### Recovery Procedures
1. **Service restart**: `docker compose restart <service>`
2. **Full rebuild**: `docker compose down && docker compose up -d`
3. **Database recovery**: Restore from mongodb_data volume backup
4. **Import data**: Use mongorestore command with backup files

## 📝 Maintenance

### Updates
- **Current version**: MongoDB 6.0 (jammy)
- **Update schedule**: Manual updates recommended
- **Update procedure**:
  1. Backup database data
  2. Update image tags
  3. Restart services
  4. Verify database integrity

### Dependencies
- **Required services**: docker-servers-net network
- **Service dependencies**: Mongo Express depends on MongoDB
- **Required by**: Applications using MongoDB storage

### Database Management
- **Admin interface**: Mongo Express (when port enabled)
- **Command line**: Available through MongoDB container
- **Backup tools**: mongodump/mongorestore available

## 🔧 Features

### MongoDB Features
- **Version**: 6.0 (stable release)
- **Storage engine**: WiredTiger (default)
- **Authentication**: Enabled with root user
- **Replication**: Single-node setup
- **Sharding**: Not configured

### Management Features
- **Web interface**: Mongo Express for database administration
- **User management**: Available through admin interface
- **Collection management**: Create, read, update, delete operations
- **Index management**: Available through interface and CLI

### Performance
- **Single instance**: Optimized for development/testing
- **Persistent storage**: Docker volumes for data persistence
- **Memory management**: Default MongoDB memory settings

## 🔗 Related Links

- [MongoDB Official Documentation](https://docs.mongodb.com/)
- [MongoDB Docker Hub](https://hub.docker.com/_/mongo)
- [Mongo Express GitHub](https://github.com/mongo-express/mongo-express)
- [MongoDB Administration](https://docs.mongodb.com/manual/administration/)

## 📅 Change Log

| Date | Change | Author |
|------|---------|---------|
| 2025-08-28 | Initial documentation | Documentation Team |

---
*Template Version: 1.0*
*Last Updated: 2025-08-28*
