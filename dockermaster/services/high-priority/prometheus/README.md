# Prometheus Monitoring Stack Documentation

## 📊 Service Overview

- **Service Name**: prometheus (monitoring stack)
- **Category**: Monitoring & Observability
- **Status**: ⚠️ NOT DEPLOYED (Critical Issue)
- **IP Address**: 192.168.59.31 (configured but not active)
- **External URL**: Not accessible (service not running)

## 🚀 Description

Comprehensive Prometheus monitoring stack designed to provide observability for all infrastructure services. The stack includes Prometheus for metrics collection, AlertManager for alerting, Node Exporter for system metrics, cAdvisor for container metrics, and SNMP Exporter for network device monitoring. This service is critical for operational visibility across the entire homelab infrastructure.

## 🔧 Configuration

### Docker Compose Location
```
/nfs/dockermaster/docker/prometheus/docker-compose.yaml
```

### Stack Components
1. **Prometheus Server**: Core metrics database and query engine
2. **Node Exporter**: System-level metrics (CPU, memory, disk, network)
3. **cAdvisor**: Container metrics (Docker stats, resource usage)
4. **AlertManager**: Alert routing and notification management
5. **SNMP Exporter**: Network device monitoring (pfSense firewall)

### Network Configuration
- **Networks**:
  - front-tier: docker-servers-net (macvlan) - IP 192.168.59.31
  - back-tier: Internal communication between components
- **Ports**:
  - Prometheus: 9090 (not exposed externally)
  - Node Exporter: 9100 (exposed to host)
  - AlertManager: 9093 (internal only)
  - cAdvisor: 8080 (internal only)

### Volumes
- `prometheus_data`: Persistent storage for metrics data
- Configuration files mounted from host:
  - `prometheus.yml`: Main Prometheus configuration
  - `snmp.yml`: SNMP exporter configuration
  - `alertmanager/config.yml`: AlertManager configuration

## 📈 Monitoring Targets

### Current Configuration
1. **Prometheus Self-Monitoring**: localhost:9090
2. **Container Metrics**: cadvisor:8080
3. **System Metrics**:
   - node-exporter:9100 (dockermaster)
   - pfsense1.srv.lcamaral.com:9482 (firewall)
4. **Network Monitoring**: 
   - SNMP monitoring of pfSense firewall
   - pfsense1.srv.lcamaral.com via SNMP exporter

### Scrape Intervals
- **Default**: 15s
- **Container metrics**: 5s
- **Node metrics**: 5s
- **SNMP metrics**: 5s

## 🚨 CRITICAL ISSUES

### 1. Service Not Deployed
- **Problem**: Entire Prometheus monitoring stack is not running
- **Impact**: NO monitoring or observability for any infrastructure services
- **Evidence**: `docker compose ps` shows no running containers
- **Risk Level**: CRITICAL - Operational blind spot

### 2. Missing Monitoring Coverage
- **Problem**: 32 services mentioned in infrastructure have no monitoring
- **Impact**: No visibility into service health, performance, or issues
- **Missing Data**:
  - Service uptime/downtime
  - Resource utilization
  - Performance metrics
  - Error rates
  - Alert notifications

### 3. Configuration Issues
- **Docker Compose Version**: Obsolete `version` attribute (warning message)
- **AlertManager**: Slack notifications not configured (commented out)
- **Alert Rules**: Referenced `alert.rules` file not found

## 🔐 Security

### Access Control
- **Prometheus UI**: No authentication configured (internal network only)
- **AlertManager**: No authentication configured
- **Network Security**: Services on internal docker network

### **⚠️ SECURITY CONSIDERATIONS**
1. **No authentication**: Services accessible without credentials on internal network
2. **No TLS**: All communication in plaintext
3. **Privileged access**: cAdvisor and node-exporter require host access

## 🔄 Backup Strategy

### Data Backup
- **Method**: Not configured
- **Metrics Data**: Stored in `prometheus_data` Docker volume
- **Recommended**: Regular volume backups or remote write to external system
- **Retention**: Default Prometheus retention (15 days)

### Configuration Backup
- **Configuration Files**: Included in dockermaster repository
- **Data Recovery**: Requires proper backup of prometheus_data volume

## 🚨 Troubleshooting

### Deployment Issues

1. **Service Not Starting**
   - **Check**: `cd /nfs/dockermaster/docker/prometheus && docker compose up -d`
   - **Logs**: `docker compose logs prometheus`
   - **Common Issues**: Configuration file errors, port conflicts

2. **Configuration Validation**
   - **Prometheus Config**: `docker exec prometheus promtool check config /etc/prometheus/prometheus.yml`
   - **Alert Rules**: Check if `alert.rules` file exists

3. **Network Connectivity**
   - **Internal**: Verify containers can reach each other
   - **External**: Test SNMP connectivity to pfSense

### Log Locations
- **Prometheus**: `docker logs prometheus`
- **Node Exporter**: `docker logs node-exporter`
- **AlertManager**: `docker logs alertmanager`
- **cAdvisor**: `docker logs cadvisor`

### Recovery Procedures
1. **Deploy monitoring stack**:
   ```bash
   cd /nfs/dockermaster/docker/prometheus
   docker compose up -d
   ```

2. **Verify services**:
   ```bash
   docker compose ps
   docker compose logs
   ```

3. **Access interfaces**:
   - Prometheus: http://192.168.59.31:9090
   - Node Exporter: http://192.168.59.31:9100

## 📝 Maintenance

### IMMEDIATE ACTIONS REQUIRED

1. **Deploy Monitoring Stack** (CRITICAL):
   ```bash
   cd /nfs/dockermaster/docker/prometheus
   # Fix docker-compose version warning
   # Deploy services
   docker compose up -d
   ```

2. **Verify Deployment**:
   ```bash
   docker compose ps
   curl http://192.168.59.31:9090/-/healthy
   ```

3. **Configure Service Discovery**:
   - Add monitoring for all 32 dockermaster services
   - Configure exporters for each service type
   - Set up proper alert rules

### Configuration Updates Needed
1. **Remove obsolete version attribute** from docker-compose.yaml
2. **Create alert.rules file** for monitoring alerts
3. **Configure AlertManager** with proper notification channels
4. **Add service discovery** for all dockermaster services

### Updates
- **Current Images**: Latest versions (may need pinning)
- **Update schedule**: Should be manual with testing
- **Compatibility**: Verify configuration compatibility with updates

### Dependencies
- **Required**: Docker network (docker-servers-net)
- **Network Access**: SNMP access to pfSense firewall
- **Storage**: Sufficient disk space for metrics retention

## 🔗 Related Links

- [Prometheus Documentation](https://prometheus.io/docs/)
- [AlertManager Documentation](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [Node Exporter](https://github.com/prometheus/node_exporter)
- [cAdvisor](https://github.com/google/cadvisor)
- [SNMP Exporter](https://github.com/prometheus/snmp_exporter)

## 📅 Change Log

| Date | Change | Author |
|------|---------|---------|
| 2023-03-26 | Initial configuration creation | System |
| 2025-08-28 | Critical issue identification - service not deployed | Documentation Specialist A |
| 2025-08-28 | Comprehensive documentation and recovery plan | Documentation Specialist A |

## 🚀 Deployment Instructions

### Quick Deploy (Emergency)
```bash
cd /nfs/dockermaster/docker/prometheus

# Fix docker-compose version warning (optional)
sed -i '/^version:/d' docker-compose.yaml

# Deploy the stack
docker compose up -d

# Verify deployment
docker compose ps
docker compose logs --tail 20
```

### Verification Steps
```bash
# Check Prometheus
curl -f http://192.168.59.31:9090/-/healthy

# Check targets are being scraped
curl -s http://192.168.59.31:9090/api/v1/targets | jq '.data.activeTargets[] | {job, health}'

# Verify data collection
curl -s http://192.168.59.31:9090/api/v1/query?query=up | jq '.data.result[] | {metric, value}'
```

### Post-Deployment Configuration
1. **Add missing alert.rules file**
2. **Configure AlertManager notifications**
3. **Set up service discovery for all 32 services**
4. **Configure Grafana dashboards for visualization**
5. **Set up backup strategy for metrics data**

---
*Template Version: 1.0*
*Last Updated: 2025-08-28*
*Service Status: NOT DEPLOYED - CRITICAL OPERATIONAL ISSUE*