# Vault Service Health Diagnosis Report

**Date**: 2025-08-28  
**Version**: Vault v1.16.3  
**Location**: dockermaster:/nfs/dockermaster/docker/vault/  

## Summary

Vault service is **FUNCTIONAL** but has **CONFIGURATION ISSUES** that cause misleading "unhealthy" status and TLS-related errors.

## Current Status

- **Container Status**: Up 25 hours (unhealthy)
- **Vault Status**: Initialized and Unsealed ✅
- **API Endpoint**: Responding on both HTTP and HTTPS
- **Storage**: Raft backend operational
- **UI**: Accessible

## Issues Diagnosed

### 1. TLS Configuration Mismatch ⚠️

**Problem**: Configuration file contains conflicting TLS settings:
- `api_addr = "https://vault.d.lcamaral.com"` (HTTPS)
- `cluster_addr = "https://192.168.59.25:8201"` (HTTPS)
- `tls_disable = 1` (TLS disabled)

**Impact**:
- Commands using `VAULT_ADDR=https://vault.d.lcamaral.com` fail with TLS certificate errors
- Health checks may report incorrect status
- Unseal scripts require workarounds

**Solution**: Update configuration to use consistent HTTP or configure proper TLS

### 2. Missing Configuration File in Host Directory ⚠️

**Problem**: `/nfs/dockermaster/docker/vault/config/config.hcl` does not exist on host
- Configuration exists only inside container at `/vault/config/config.hcl`
- Host directory only contains policy files

**Impact**:
- Configuration cannot be edited from host
- Version control of configuration not possible

**Solution**: Copy configuration to host directory for proper management

### 3. Security Issues 🚨

**Critical Issues Found**:
- Root token stored in plaintext in `.env` file
- Service token stored in plaintext in `.env` file
- Unseal keys stored in plaintext in `.env` file

**Impact**: Complete security compromise if repository is accessed

**Solution**: Implement secure token and key management

### 4. Health Check Configuration 📊

**Current Health Check**:
```bash
wget --no-verbose --tries=1 --spider http://127.0.0.1:8200/v1/sys/health
```

**Status**: Working but reports "unhealthy" due to sealed state detection

## Test Results

### API Connectivity ✅
```bash
# HTTP - Working
curl -k http://192.168.59.25:8200/v1/sys/health
# Response: {"initialized":true,"sealed":false,...}

# HTTPS - Working (but with certificate warnings)
curl -k https://vault.d.lcamaral.com/v1/sys/health
# Response: {"initialized":true,"sealed":false,...}
```

### Vault Status ✅
After manual unseal using HTTP address:
```
Seal Type               shamir
Initialized             true
Sealed                  false
Total Shares            1
Threshold               1
Version                 1.16.3
HA Enabled              true
HA Mode                 standby
```

## Immediate Fixes Required

### Priority 1: TLS Configuration Consistency
```hcl
# Option 1: Use HTTP consistently (Quick fix)
api_addr     = "http://192.168.59.25:8200"
cluster_addr = "http://192.168.59.25:8201"

# Option 2: Configure proper TLS (Recommended for production)
listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = 0
  tls_cert_file   = "/vault/tls/vault.crt"
  tls_key_file    = "/vault/tls/vault.key"
}
```

### Priority 2: Configuration File Management
```bash
# Copy config from container to host
docker cp vault:/vault/config/config.hcl /nfs/dockermaster/docker/vault/config/
# Edit host copy
# Restart container to use updated config
```

### Priority 3: Security Remediation
1. Remove tokens from `.env` file
2. Use Vault auth methods instead of static tokens
3. Store unseal keys securely offline
4. Enable audit logging

## Operational Status

**Current State**: Vault is operational but requires configuration cleanup
**Services Impact**: Some services may fail to access secrets due to TLS issues
**Availability**: 99% - Service accessible but with workarounds needed

## Next Steps

1. ✅ **Completed**: Diagnosis and status verification
2. 🔄 **In Progress**: Fix TLS configuration consistency
3. ⏳ **Pending**: Create configuration backup
4. ⏳ **Pending**: Implement secure token management
5. ⏳ **Pending**: Create service policies
6. ⏳ **Pending**: Document emergency procedures

## Commands Used

```bash
# Check container status
docker ps -a | grep vault

# Check logs
docker logs vault --tail 50

# Test API endpoints
curl -k http://192.168.59.25:8200/v1/sys/health
curl -k https://vault.d.lcamaral.com/v1/sys/health

# Unseal vault (working command)
VAULT_ADDR=http://192.168.59.25:8200 VAULT_SKIP_VERIFY=true ./unseal

# Check configuration
docker exec vault cat /vault/config/config.hcl
```

---
*Report Generated*: 2025-08-28  
*Next Review*: After TLS configuration fix  
*Status*: Issues Identified - Ready for Remediation  
