# OpenTelemetry Home Service Documentation

## 📊 Service Overview

- **Service Name**: opentelemetry-home
- **Category**: Observability / Monitoring Stack
- **Status**: Active
- **IP Address Range**: 192.168.59.31-34
- **External URL**: Various service endpoints on internal network

## 🚀 Description

OpenTelemetry Home is a comprehensive observability stack that provides distributed tracing, metrics collection, and monitoring capabilities for the home infrastructure. It includes OpenTelemetry Collector, Jaeger for tracing, Prometheus for metrics, and Grafana for visualization, creating a complete observability solution.

## 🔧 Configuration

### Docker Compose Location
```
/nfs/dockermaster/docker/opentelemetry-home/docker-compose.yaml
```

### Service Architecture
The stack consists of four interconnected services:
- **otelcol**: OpenTelemetry Collector for data collection and processing
- **jaeger**: Distributed tracing backend with UI
- **prometheus**: Metrics collection and storage
- **grafana**: Visualization and dashboards

### Environment Variables
- **OpenTelemetry Collector**:
  - `OTEL_COLLECTOR_IP`: 192.168.59.31
  - `OTEL_COLLECTOR_HOST`: otelcol
  - `OTEL_COLLECTOR_PORT`: 4317 (gRPC)
  - `OTEL_COLLECTOR_PUBLIC_PORT`: 4318 (HTTP)

- **Jaeger**:
  - `JAEGER_IP`: 192.168.59.32
  - `JAEGER_SERVICE_PORT`: 16686
  - `JAEGER_SERVICE_HOST`: jaeger

- **Prometheus**:
  - `PROMETHEUS_IP`: 192.168.59.34
  - `PROMETHEUS_SERVICE_PORT`: 9090
  - `PROMETHEUS_ADDR`: prometheus:9090

- **Grafana**:
  - `GRAFANA_IP`: 192.168.59.33
  - `GRAFANA_SERVICE_PORT`: 3000

- **Application Settings**:
  - `OTEL_RESOURCE_ATTRIBUTES`: service.namespace=oteld.home.lcamaral.com
  - `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE`: cumulative

### Volumes
- `/nfs/dockermaster/docker/opentelemetry-home/otel-collector`: Collector configuration
- `/nfs/dockermaster/docker/opentelemetry-home/grafana/cfg`: Grafana configuration
- `/nfs/dockermaster/docker/opentelemetry-home/grafana/provisioning`: Dashboard provisioning
- `/nfs/dockermaster/docker/opentelemetry-home/prometheus`: Prometheus configuration

### Network Configuration
- **Network**: docker-servers-net (macvlan)
- **IP Addresses**:
  - OpenTelemetry Collector: 192.168.59.31
  - Jaeger: 192.168.59.32
  - Grafana: 192.168.59.33
  - Prometheus: 192.168.59.34
- **Ports**:
  - OTLP gRPC: 4317
  - OTLP HTTP: 4318
  - Prometheus: 9090
  - Jaeger UI: 16686
  - Grafana: 3000

## 🔐 Security

### Secrets Management
- Configuration files stored in mounted volumes
- No explicit authentication configured (internal network)

### Access Control
- **Network access**: Limited to docker-servers-net
- **Authentication**: Default service authentication (if any)

## 📈 Monitoring

### Health Checks
- **Current**: No explicit health checks configured
- **Service monitoring**: Self-monitoring through the stack itself
- **Endpoints**: Each service provides its own health/status endpoints

### Metrics
- **Prometheus**: Central metrics collection
- **OTLP metrics**: Collected via OpenTelemetry Collector
- **Service metrics**: Available on port 9464 (Collector) and 8888 (metrics endpoint)

## 🔄 Backup Strategy

### Data Backup
- **Configuration files**: Stored in mounted directories
- **Time-series data**: Prometheus data (1h retention configured)
- **Traces**: Jaeger data (10,000 max traces in memory)

### Configuration Backup
- **Git repository**: Yes - all configuration files included
- **Provisioning**: Grafana dashboards and data sources

## 🚨 Troubleshooting

### Common Issues
1. **Issue**: OpenTelemetry Collector not receiving data
   - **Symptoms**: No traces or metrics appearing
   - **Solution**: Check OTLP endpoint configuration and network connectivity

2. **Issue**: Jaeger UI not showing traces
   - **Symptoms**: Empty trace view
   - **Solution**: Verify Collector is forwarding traces to Jaeger

3. **Issue**: Grafana dashboards not loading data
   - **Symptoms**: No data in visualizations
   - **Solution**: Check Prometheus data source configuration

### Log Locations
- **Container logs**: 
  - `docker logs otel-col`
  - `docker logs jaeger`
  - `docker logs prometheus`
  - `docker logs grafana`
- **Log configuration**: JSON file driver with 5MB max size, 2 files

### Recovery Procedures
1. **Service restart**: `docker compose restart <service>`
2. **Full rebuild**: `docker compose down && docker compose up -d`
3. **Configuration reload**: Prometheus supports hot reload via API
4. **Clear data**: Restart services to clear in-memory data

## 📝 Maintenance

### Updates
- **OpenTelemetry Collector**: v0.76.1
- **Jaeger**: Latest (all-in-one)
- **Prometheus**: v2.43.0
- **Grafana**: v9.4.7
- **Update procedure**: Update image tags and recreate containers

### Dependencies
- **Service startup order**: jaeger → otelcol → prometheus, grafana
- **Cross-service dependencies**: Configured via environment variables
- **Required by**: Applications using OpenTelemetry instrumentation

### Resource Limits
- **OpenTelemetry Collector**: 125MB memory limit
- **Jaeger**: 300MB memory limit, 10,000 max traces
- **Prometheus**: 300MB memory limit, 1h retention
- **Grafana**: 100MB memory limit

## 🔧 Features

### OpenTelemetry Collector
- **Protocols**: OTLP gRPC and HTTP
- **Configuration**: /etc/cfg/config.devhome.yaml
- **Exporters**: Jaeger and Prometheus integration

### Jaeger Features
- **Tracing**: Distributed trace collection and analysis
- **UI**: Web interface on port 16686
- **Storage**: In-memory with configurable limits
- **Integration**: Prometheus metrics integration

### Prometheus Features
- **Metrics**: Time-series metrics collection
- **Retention**: 1 hour (configured for testing)
- **Features**: Exemplar storage enabled
- **Web interface**: Available on port 9090

### Grafana Features
- **Dashboards**: Pre-provisioned dashboards
- **Data sources**: Prometheus and Jaeger integration
- **Configuration**: Custom grafana.ini
- **Visualizations**: Complete observability dashboards

## 🔗 Related Links

- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Jaeger Documentation](https://www.jaegertracing.io/docs/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)

## 📅 Change Log

| Date | Change | Author |
|------|---------|---------|
| 2025-08-28 | Initial documentation | Documentation Team |

---
*Template Version: 1.0*
*Last Updated: 2025-08-28*