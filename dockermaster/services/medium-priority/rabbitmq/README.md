# RabbitMQ Service Documentation

## 📊 Service Overview

- **Service Name**: rabbitmq
- **Category**: Message Queue / Broker
- **Status**: Active
- **IP Address**: 192.168.59.24
- **External URL**: rmq.d.lcamaral.com

## 🚀 Description

RabbitMQ is a message broker service that implements the Advanced Message Queuing Protocol (AMQP). It serves as the central messaging system for the home infrastructure, supporting both AMQP and MQTT protocols for reliable message queuing and publishing/subscribing patterns.

## 🔧 Configuration

### Docker Compose Location
```
/nfs/dockermaster/docker/rabbitmq/docker-compose.yml
```

### Environment Variables
- **Required**:
  - `RABBITMQ_HOST`: rmq.d.lcamaral.com
  - `RABBITMQ_DEFAULT_USER`: kalo
  - `RABBITMQ_DEFAULT_PASS`: kalo24eb8a3dacb63b1e6205c774232a0834

### Volumes
- `rabbitmq-lib`: Main RabbitMQ data directory (/var/lib/rabbitmq/)
- `rabbitmq-log`: Log files (/var/log/rabbitmq/)
- `./config`: Configuration files mounted as read-only

### Network Configuration
- **Network**: docker-servers-net (macvlan)
- **IP**: 192.168.59.24
- **Ports**:
  - Internal: 5672 (AMQP)
  - Internal: 1883 (MQTT)
  - Management UI: 15672 (implied by management plugin)

## 🔐 Security

### Secrets Management
- Basic authentication configured with default user/password
- MQTT configured to disallow anonymous access
- TLS configuration available but currently commented out

### Access Control
- Authentication method: Basic Auth (username/password)
- Default user: kalo
- MQTT anonymous access: disabled

## 📈 Monitoring

### Health Checks
- **Endpoint**: rabbitmq-diagnostics -q ping
- **Interval**: 30s
- **Timeout**: 4s
- **Retries**: 15

### Metrics
- **Prometheus**: Not explicitly configured
- **Management Plugin**: Enabled (rabbitmq_management)
- **Custom dashboards**: Management UI available

## 🔄 Backup Strategy

### Data Backup
- **Method**: Volume-based backup
- **Frequency**: As per volume backup schedule
- **Location**: Local Docker volumes (rabbitmq-lib, rabbitmq-log)

### Configuration Backup
- **Git repository**: Yes - included in dockermaster repo
- **Config files**: /config directory with rabbitmq.conf and enabled_plugins

## 🔧 Service Features

### Enabled Plugins
- **rabbitmq_management**: Web-based management interface
- **rabbitmq_mqtt**: MQTT protocol support

### Protocol Support
- **AMQP**: Default messaging protocol (port 5672)
- **MQTT**: IoT messaging protocol (port 1883)

### Resource Limits
- **CPU Limits**: 2 cores maximum
- **Memory Limits**: 2GB maximum
- **CPU Reservations**: 0.5 cores minimum
- **Memory Reservations**: 512MB minimum

## 🚨 Troubleshooting

### Common Issues
1. **Issue**: Container fails to start
   - **Symptoms**: Container exits immediately
   - **Solution**: Check configuration files and ensure proper permissions

2. **Issue**: MQTT connections refused
   - **Symptoms**: MQTT clients cannot connect
   - **Solution**: Verify MQTT plugin is enabled and port 1883 is accessible

### Log Locations
- **Container logs**: `docker logs rabbitmq`
- **RabbitMQ logs**: Volume `rabbitmq-log` (/var/log/rabbitmq/)

### Recovery Procedures
1. **Service restart**: `docker compose restart rabbitmq`
2. **Full rebuild**: `docker compose down && docker compose up -d`
3. **Reset data**: Remove rabbitmq-lib volume (WARNING: data loss)

## 📝 Maintenance

### Updates
- **Update schedule**: Manual updates only (Watchtower disabled)
- **Update procedure**: 
  1. Stop service
  2. Pull new image
  3. Restart service
  4. Verify functionality

### Dependencies
- **Required services**: docker-servers-net network
- **Required by**: Services using message queuing (unknown without further analysis)

### Configuration Files
```
config/
├── rabbitmq.conf          # Main configuration
└── enabled_plugins        # Plugin configuration
```

## 🔗 Related Links

- [RabbitMQ Official Documentation](https://www.rabbitmq.com/documentation.html)
- [RabbitMQ Docker Hub](https://hub.docker.com/_/rabbitmq)
- [RabbitMQ Management Plugin](https://www.rabbitmq.com/management.html)
- [MQTT Plugin Documentation](https://www.rabbitmq.com/mqtt.html)

## 📅 Change Log

| Date | Change | Author |
|------|---------|---------|
| 2025-08-28 | Initial documentation | Documentation Team |

---
*Template Version: 1.0*
*Last Updated: 2025-08-28*