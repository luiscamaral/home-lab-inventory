# [SERVICE_NAME] Service Documentation

## 📊 Service Overview

- **Service Name**: [SERVICE_NAME]
- **Category**: [Web App/Database/Proxy/Monitoring/etc]
- **Status**: [Active/Planned/Deprecated]
- **IP Address**: [192.168.59.X]
- **External URL**: [https://service.d.lcamaral.com]

## 🚀 Description

[Brief description of what this service does and why it's needed]

## 🔧 Configuration

### Docker Compose Location

```text
/nfs/dockermaster/docker/[service-name]/docker-compose.yml
```

### Environment Variables

- **Required**:
  - `VARIABLE_NAME`: Description
- **Optional**:
  - `OPTIONAL_VAR`: Description with default value

### Volumes

- `service_data`: Main application data
- `service_config`: Configuration files
- `service_logs`: Log files (if separate)

### Network Configuration

- **Network**: Docker-servers-net (macvlan)
- **IP**: 192.168.59.X
- **Ports**:
  - Internal: [port]
  - External: [port] (if applicable)

## 🔐 Security

### Secrets Management

- Secrets stored in Vault: `http://vault.d.lcamaral.com`
- Vault path: `secret/dockermaster/[service-name]`

### Access Control

- Authentication method: [OAuth/Basic Auth/None]
- Authorized users: [list or reference]

## 📈 Monitoring

### Health Checks

- **Endpoint**: [/health or /healthz]
- **Interval**: [30s]
- **Timeout**: [10s]

### Metrics

- **Prometheus**: [Yes/No]
- **Metrics endpoint**: [/metrics]
- **Custom dashboards**: [Grafana dashboard ID]

## 🔄 Backup Strategy

### Data Backup

- **Method**: [Automated/Manual]
- **Frequency**: [Daily/Weekly]
- **Location**: [/nfs/backups/service-name]

### Configuration Backup

- **Git repository**: [Yes - included in dockermaster repo]
- **Manual backups**: [Location if applicable]

## 🚨 Troubleshooting

### Common Issues

1. **Issue**: Description
   - **Symptoms**: What you see
   - **Solution**: How to fix

### Log Locations

- **Container logs**: `docker logs [container-name]`
- **Application logs**: [specific paths if applicable]

### Recovery Procedures

1. **Service restart**: `docker compose restart [service]`
2. **Full rebuild**: `docker compose down && docker compose up -d`
3. **Data recovery**: [specific steps]

## 📝 Maintenance

### Updates

- **Update schedule**: [Monthly/As needed]
- **Update procedure**: [steps]

### Dependencies

- **Required services**: [list of dependent services]
- **Required by**: [services that depend on this one]

## 🔗 Related Links

- [Official Documentation](url)
- [GitHub Repository](url)
- [Docker Hub](url)
- [Internal Wiki](url)

## 📅 Change Log

| Date | Change | Author |
|------|---------|---------|
| YYYY-MM-DD | Initial deployment | [Name] |

---
_Template Version: 1.0_
_Last Updated: [DATE]_
