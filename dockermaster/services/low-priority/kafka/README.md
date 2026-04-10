# Kafka Service Documentation

## 📊 Service Overview

- **Service Name**: kafka
- **Category**: Message Streaming Platform
- **Status**: Active
- **IP Address**: 192.168.59.35
- **External URL**: Not configured (internal service)

## 🚀 Description

Apache Kafka is a distributed streaming platform that handles real-time data feeds. This service runs Kafka in KRaft mode (Kafka Raft), which eliminates the need for Apache Zookeeper by using Kafka's internal consensus protocol. It provides high-throughput, fault-tolerant stream processing capabilities.

## 🔧 Configuration

### Docker Compose Location
```
/nfs/dockermaster/docker/kafka/docker-compose.yaml
```

### Service Architecture
- **kafka**: Single-node Kafka broker running in KRaft mode
- **Version**: Bitnami Kafka 3.4
- **Mode**: KRaft (no Zookeeper required)

### Environment Variables
- **Core Configuration**:
  - `ALLOW_PLAINTEXT_LISTENER`: true (no encryption)
  - `KAFKA_BROKER_ID`: 1
  - `KAFKA_KRAFT_CLUSTER_ID`: NmYxODQ4YWNiMjY2NDY5ZT (KAFKA_HOME_LCAMARAL_COM)
  - `KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR`: 1

- **Topic Configuration**:
  - `KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE`: true
  - `KAFKA_CREATE_TOPICS`: "User:1:3,Project:1:1:compact"

- **Debugging**:
  - `BITNAMI_DEBUG`: true

- **Network Configuration**:
  - `KAFKA_IP`: 192.168.59.35 (from .env file)

### Volumes
- `kafka_data`: Persistent storage for Kafka data and logs (mapped to /bitnami)

### Network Configuration
- **Network**: docker-servers-net (macvlan)
- **IP**: 192.168.59.35
- **Ports**:
  - 9092: Default Kafka port
  - 9093: Additional listener port
  - 9094: Additional listener port

## 🔐 Security

### Secrets Management
- **Current setup**: Plaintext listeners enabled (no authentication)
- **Security level**: Low (internal network only)

### Access Control
- **Authentication**: None (plaintext listeners)
- **Authorization**: Not configured
- **Network access**: Limited to docker-servers-net

## 📈 Monitoring

### Health Checks
- **Current**: No explicit health checks configured
- **Monitoring**: Available through Kafka JMX metrics
- **Debug logs**: Enabled via BITNAMI_DEBUG

### Metrics
- **JMX**: Available on default Kafka JMX ports
- **Prometheus**: Not explicitly configured
- **Custom dashboards**: Would require external monitoring setup

## 🔄 Backup Strategy

### Data Backup
- **Method**: Volume backup of kafka_data volume
- **Frequency**: Depends on volume backup schedule
- **Location**: Docker local volume

### Configuration Backup
- **Git repository**: Yes - docker-compose.yaml and .env included
- **Topic configuration**: Auto-created topics defined in environment

## 🚨 Troubleshooting

### Common Issues
1. **Issue**: Kafka broker fails to start
   - **Symptoms**: Container exits or restart loops
   - **Solution**: Check logs for KRaft initialization issues

2. **Issue**: Topics not auto-created
   - **Symptoms**: Applications cannot find topics
   - **Solution**: Verify KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE setting

3. **Issue**: Connection refused from applications
   - **Symptoms**: Clients cannot connect to Kafka
   - **Solution**: Check network connectivity and listener configuration

### Log Locations
- **Container logs**: `docker logs <kafka-container-name>`
- **Kafka logs**: Available in kafka_data volume under /bitnami/kafka/logs

### Recovery Procedures
1. **Service restart**: `docker compose restart kafka`
2. **Full rebuild**: `docker compose down && docker compose up -d`
3. **Data recovery**: Restore from kafka_data volume backup
4. **Reset Kafka**: Remove kafka_data volume (WARNING: data loss)

## 📝 Maintenance

### Updates
- **Current version**: Bitnami Kafka 3.4
- **Update schedule**: Manual updates recommended
- **Update procedure**:
  1. Stop Kafka service
  2. Backup kafka_data volume
  3. Update image tag
  4. Restart service
  5. Verify topic integrity

### Dependencies
- **Required services**: docker-servers-net network
- **Required by**: Applications using Kafka streaming
- **External dependencies**: None (KRaft mode)

### Topic Management
- **Pre-created topics**:
  - `User`: 1 partition, replication factor 3
  - `Project`: 1 partition, replication factor 1, compacted
- **Auto-creation**: Enabled for additional topics

## 🔧 Features

### Kafka Configuration
- **Mode**: KRaft (no Zookeeper)
- **Replication**: Single-node setup
- **Partitioning**: Configurable per topic
- **Compression**: Available (not specifically configured)

### Topic Features
- **Auto-creation**: Enabled
- **Compaction**: Available (Project topic uses compaction)
- **Retention**: Default Kafka retention policies
- **Multiple partitions**: Supported

### Performance
- **Single broker**: Optimized for development/testing
- **Local storage**: Uses Docker volumes for persistence
- **Debug mode**: Enabled for troubleshooting

## 🔗 Related Links

- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Bitnami Kafka Docker](https://hub.docker.com/r/bitnami/kafka)
- [KRaft Mode Documentation](https://kafka.apache.org/documentation/#kraft)
- [Kafka Configuration Reference](https://kafka.apache.org/documentation/#configuration)

## 📅 Change Log

| Date | Change | Author |
|------|---------|---------|
| 2025-08-28 | Initial documentation | Documentation Team |

---
*Template Version: 1.0*
*Last Updated: 2025-08-28*
