# Vault Integration Plan for Dockermaster Services

## Overview
HashiCorp Vault is active at https://vault.d.lcamaral.com/ and will provide centralized secret management for all dockermaster services.

## Secret Organization Structure
```
secrets/
└── homelab/
    ├── portainer/
    │   ├── admin_password
    │   ├── api_key
    │   └── db_credentials
    ├── keycloak/
    │   ├── admin_password
    │   ├── db_password
    │   └── client_secrets
    ├── github-runner/
    │   ├── github_token
    │   └── runner_token
    └── [service-name]/
        └── [secret-key]
```

## Authentication Strategy

### Primary: AppRole Authentication
- Each service gets its own AppRole with specific policies
- Role ID embedded in docker-compose
- Secret ID injected at runtime via init container

### Init Container Approach
```yaml
services:
  vault-init:
    image: vault:latest
    command: |
      sh -c "
      export VAULT_ADDR=https://vault.d.lcamaral.com
      vault login -method=approle role_id=$ROLE_ID secret_id=$SECRET_ID
      vault kv get -format=json secrets/homelab/service-name > /shared/secrets.json
      "
    volumes:
      - secrets-volume:/shared

  main-service:
    depends_on:
      vault-init:
        condition: service_completed_successfully
    volumes:
      - secrets-volume:/secrets:ro
```

## Migration Priority

### Phase 1 - Critical Services (Immediate)
1. **Portainer** - Central container management
   - Admin credentials
   - API keys
   - Database passwords

2. **Keycloak** - Authentication provider
   - Admin credentials
   - Database passwords
   - Client secrets
   - Realm configurations

### Phase 2 - High Priority Services
3. **GitHub Runner** - CI/CD credentials
4. **Vault** - Self-management tokens
5. **Prometheus** - Monitoring credentials

### Phase 3 - Standard Services
- All remaining services alphabetically

## Integration Templates

### Docker Compose Template with Vault
```yaml
name: service-name

services:
  # Vault init container for secret retrieval
  vault-agent:
    image: vault:latest
    container_name: ${SERVICE_NAME}-vault-init
    environment:
      VAULT_ADDR: https://vault.d.lcamaral.com
      SERVICE_NAME: ${SERVICE_NAME}
    volumes:
      - ./vault-config:/vault/config:ro
      - secrets:/vault/secrets
    command: |
      sh -c "
      vault agent -config=/vault/config/agent.hcl
      "

  main-service:
    image: service:latest
    container_name: ${SERVICE_NAME}
    depends_on:
      vault-agent:
        condition: service_completed_successfully
    env_file:
      - /vault/secrets/service.env
    volumes:
      - secrets:/vault/secrets:ro
```

### Vault Agent Configuration (agent.hcl)
```hcl
vault {
  address = "https://vault.d.lcamaral.com"
}

auto_auth {
  method {
    type = "approle"
    config {
      role_id_file_path = "/vault/config/role_id"
      secret_id_file_path = "/vault/config/secret_id"
    }
  }

  sink {
    type = "file"
    config {
      path = "/vault/secrets/token"
    }
  }
}

template {
  source = "/vault/config/service.env.tpl"
  destination = "/vault/secrets/service.env"
}
```

## Implementation Steps

### For Each Service:
1. Create AppRole in Vault
2. Define policy for service-specific secrets
3. Create secret path: `secrets/homelab/<service-name>/`
4. Add init container to docker-compose
5. Update environment variables to read from mounted secrets
6. Test service startup with Vault integration
7. Document emergency fallback procedures

## Emergency Procedures

### If Vault is Unavailable:
1. Check Vault service status at https://vault.d.lcamaral.com/
2. Use emergency sealed env files (encrypted with GPG)
3. Fallback to local .env files (temporary)
4. Alert procedures documented per service

### Secret Rotation:
1. Update secret in Vault
2. Restart service with docker-compose
3. Verify service health
4. Update backup sealed files

## Security Considerations
- Never commit actual secrets to Git
- Use `.env.example` files with placeholders
- Implement secret rotation schedule
- Monitor Vault audit logs
- Backup Vault data regularly

## Next Steps
1. ✅ Document Vault integration approach (this document)
2. ⏳ Create AppRoles for Portainer and Keycloak
3. ⏳ Migrate Portainer secrets to Vault
4. ⏳ Migrate Keycloak secrets to Vault
5. ⏳ Create automated migration scripts
6. ⏳ Test emergency procedures

## Related Documentation
- [Vault Service Documentation](../dockermaster/services/high-priority/vault/README.md)
- [Service Migration Status](./service-migration-status.md)
- [Emergency Procedures](./emergency-procedures.md)

---
*Last Updated: 2025-08-28*
*Status: Planning Phase*
