# Vault Service Documentation

## 📊 Service Overview

- **Service Name**: vault
- **Category**: Secret Management
- **Status**: Running but Unhealthy (TLS Configuration Issues)
- **IP Address**: 192.168.59.25
- **External URL**: <https://vault.d.lcamaral.com> (Currently not working)

## 🚀 Description

HashiCorp Vault service providing centralized secret management for the dockermaster infrastructure. This service stores and manages sensitive data such as API keys, passwords, certificates, and other secrets used by various services in the homelab environment.

## 🔧 Configuration

### Docker Compose Location

```
/nfs/dockermaster/docker/vault/docker-compose.yml
```

### Environment Variables

- **Required**:
  - `VAULT_ADDR`: Vault server address (<http://vault.d.lcamaral.com/>)
- **Present** (Should be managed securely):
  - `ROOT_TOKEN`: <STORED IN VAULT — rotate if exposed>
  - `VAULT_TOKEN`: <STORED IN VAULT — rotate if exposed>
  - `VAULT_UNSEAL_KEYS`: <STORED OFFLINE — never commit to git>

### Volumes

- `./vault/config:/vault/config`: Configuration files and policies
- `./vault/data:/vault/data`: Raft storage backend data
- `./vault/logs:/vault/logs`: Vault service logs

### Network Configuration

- **Network**: Docker-servers-net (macvlan)
- **IP**: 192.168.59.25
- **Ports**:
  - Internal: 8200 (API)
  - Internal: 8201 (Cluster)
- **TLS**: Disabled for local connection, HTTPS expected for external access

## 🔐 Security

### Current Security Configuration

- **Storage Backend**: Raft (High Availability capable)
- **Seal Type**: Shamir's Secret Sharing
- **UI**: Enabled
- **mlock**: Disabled (disable_mlock = true)
- **TLS**: Disabled for local listeners, expected for API access

### Access Control Policies

Available policy files:

- `kv-app-readonly.hcl`: Read-only access to KV store
- `project-dockermaster-home-lab-inventory.hcl`: Project-specific access
- `project-dockermaster-home-lab-inventory-ro.hcl`: Read-only project access
- `superuser.hcl`: Administrative access

### **⚠️ CRITICAL SECURITY ISSUES**

1. **Root token in environment file**: Highly insecure, should be removed after initial setup
2. **Service token in plaintext**: Should use dynamic tokens or proper authentication
3. **Unseal keys in plaintext**: Should be stored securely, not in version control

## 📈 Monitoring

### Health Checks

- **Endpoint**: `http://127.0.0.1:8200/v1/sys/health`
- **Interval**: 10s
- **Timeout**: 3s
- **Retries**: 10
- **Current Status**: Unhealthy (TLS configuration mismatch)

### Resource Limits

- **CPU Limit**: 2 cores
- **Memory Limit**: 2GB
- **CPU Reservation**: 0.5 cores
- **Memory Reservation**: 512MB

### Metrics

- **Prometheus**: Not configured (should be enabled)
- **Metrics endpoint**: `/v1/sys/metrics` (available but not exposed)
- **Telemetry**: Not configured

## 🚨 Current Issues

### 1. TLS Configuration Mismatch

- **Problem**: API address configured as HTTPS but TLS disabled on listeners
- **Impact**: Unseal scripts fail, external access fails
- **Error**: `certificate signed by unknown authority`

### 2. Vault Sealed State

- **Problem**: Vault may be sealed and unseal script failing due to TLS issues
- **Impact**: Secrets inaccessible to dependent services
- **Status**: Requires manual investigation

### 3. Configuration File Location Mismatch

- **Problem**: Docker-compose references `/vault/config/config.hcl` but file is at `/vault/config/config.hcl`
- **Impact**: May not be using correct configuration
- **Status**: Needs verification

## 🔄 Backup Strategy

### Data Backup

- **Method**: Manual (Raft snapshots recommended)
- **Frequency**: Should be daily
- **Location**: Not currently configured
- **Command**: `vault operator raft snapshot save backup.snap`

### Configuration Backup

- **Git repository**: Partially (policies included, sensitive data excluded)
- **Unseal keys**: ⚠️ Currently in environment file (INSECURE)
- **Recovery keys**: Should be stored in secure offline location

## 🚨 Troubleshooting

### Common Issues

1. **Vault Sealed**
   - **Symptoms**: "Vault is sealed" errors, services can't access secrets
   - **Solution**: Use unseal script (fix TLS issues first)
   - **Command**: `./unseal` (after fixing HTTPS/HTTP mismatch)

2. **TLS Certificate Errors**
   - **Symptoms**: "certificate signed by unknown authority"
   - **Solution**: Either configure proper TLS or use HTTP for unseal script
   - **Workaround**: Set `VAULT_SKIP_VERIFY=true`

3. **Health Check Failures**
   - **Symptoms**: Container shows as unhealthy
   - **Investigation**: Check `docker logs vault` for startup issues
   - **Solution**: Verify configuration file path and unsealing

### Log Locations

- **Container logs**: `docker logs vault`
- **Vault logs**: `/nfs/dockermaster/docker/vault/vault/logs/`
- **Audit logs**: Not configured (recommended to enable)

### Recovery Procedures

1. **Unseal vault**: Fix TLS configuration, then run `./unseal`
2. **Service restart**: `docker compose restart vault`
3. **Full rebuild**: `docker compose down && docker compose up -d`
4. **Emergency access**: Use root token (if available and valid)

## 📝 Maintenance

### Critical Actions Needed

1. **Fix TLS configuration**: Either enable proper TLS or update unseal script to use HTTP
2. **Secure token management**: Remove tokens from environment files
3. **Configure backups**: Implement automated Raft snapshots
4. **Enable audit logging**: For security compliance
5. **Configure Prometheus monitoring**: For operational visibility

### Updates

- **Current Version**: Vault v1.16.3
- **Update schedule**: Manual (Watchtower disabled)
- **Update procedure**: Test in staging, backup first, then update

### Dependencies

- **Required services**: Docker-servers-net network
- **Required by**: All services using secrets (GitHub-runner, keycloak, etc.)

## 🔗 Related Links

- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [Vault Docker Image](https://hub.docker.com/_/vault)
- [Raft Storage Backend](https://www.vaultproject.io/docs/configuration/storage/raft)
- [Vault Unsealing](https://www.vaultproject.io/docs/concepts/seal)

## 📅 Change Log

| Date | Change | Author |
|------|---------|---------|
| 2025-08-26 | Service configuration and deployment | System |
| 2025-08-27 | Unseal script creation and debugging | System |
| 2025-08-28 | Issue identification and documentation | Documentation Specialist A |

## 🔧 Immediate Action Items

### High Priority Fixes

1. **Resolve TLS Configuration**

   ```bash
   # Option 1: Use HTTP for unseal (Quick fix)
   # Edit unseal script: Change VAULT_ADDR to "http://192.168.59.25:8200"

   # Option 2: Configure proper TLS (Recommended)
   # Set up nginx proxy with proper certificates
   ```

2. **Secure Token Management**

   ```bash
   # Remove tokens from .env file
   # Use vault authentication methods instead
   # Store unseal keys securely offline
   ```

3. **Test Unsealing Process**

   ```bash
   # After fixing TLS issues:
   cd /nfs/dockermaster/docker/vault
   ./unseal
   vault status
   ```

### Configuration Template for HTTP Mode

```hcl
# For immediate fix, update config.hcl:
api_addr     = "http://192.168.59.25:8200"  # Use HTTP instead of HTTPS
cluster_addr = "http://192.168.59.25:8201"   # Use HTTP instead of HTTPS
```

---
_Template Version: 1.0_
_Last Updated: 2025-08-28_
_Service Status: Running but Unhealthy - Requires TLS Configuration Fix_
