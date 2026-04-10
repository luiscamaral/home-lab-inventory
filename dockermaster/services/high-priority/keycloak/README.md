# Keycloak Service Documentation

## 📊 Service Overview

- **Service Name**: keycloak
- **Category**: Authentication & Identity Management
- **Status**: Starting (Database Authentication Issues)
- **IP Address**: 192.168.59.13
- **External URL**: https://keycloak.d.lcamaral.com

## 🚀 Description

Keycloak identity and access management service providing single sign-on (SSO), user authentication, authorization, and identity brokering for the homelab infrastructure. This service centralizes authentication for all connected applications and services, supporting multiple protocols including OAuth 2.0, OpenID Connect, and SAML.

## 🔧 Configuration

### Docker Compose Location
```
/nfs/dockermaster/docker/keycloak/docker-compose.yml
```

### Environment Variables
- **Required**:
  - `KC_DB_PASSWORD`: PostgreSQL database password for keycloak user
  - `KEYCLOAK_ADMIN_PASSWORD`: Admin console password for 'admin' user
- **Configured**:
  - `KC_PROXY_HEADERS`: xforwarded (for reverse proxy support)
  - `KC_HTTP_ENABLED`: true (HTTP enabled for internal access)
  - `KC_HOSTNAME`: keycloak.d.lcamaral.com
  - `KC_DB`: postgres (using PostgreSQL backend)
  - `KC_DB_URL`: jdbc:postgresql://postgres:5432/keycloak
  - `KC_DB_USERNAME`: keycloak
  - `KEYCLOAK_ADMIN`: admin

### Volumes
- `./keycloak_data:/opt/keycloak/data/h2`: Keycloak data storage
- `./postgres_data:/var/lib/postgresql/data`: PostgreSQL database files

### Network Configuration
- **Networks**:
  - docker-servers-net (macvlan): 192.168.59.13
  - bridge (keycloak): Internal communication with PostgreSQL
- **Ports**:
  - Internal: 8080 (HTTP)
  - External: Accessed via reverse proxy

## 🗄️ Database Configuration

### PostgreSQL Backend
- **Image**: postgres:17
- **Container**: postgres
- **Database**: keycloak
- **User**: keycloak
- **Network**: keycloak bridge network (internal)
- **Data Location**: `./postgres_data`

### Database Status
- **Connection**: Database exists and user can connect
- **Health**: PostgreSQL container is healthy
- **Issue**: Keycloak experiencing authentication failures during startup

## 🔐 Security

### Authentication
- **Admin User**: admin
- **Admin Password**: Stored in environment (should migrate to Vault)
- **Database Password**: Stored in environment (should migrate to Vault)

### Access Control
- **Reverse Proxy**: Expected to be behind nginx with TLS termination
- **HTTP Enabled**: For internal communication
- **Proxy Headers**: Configured to trust X-Forwarded headers

### **⚠️ SECURITY CONCERNS**
1. **Passwords in plaintext**: Environment file contains sensitive passwords
2. **Admin credentials**: Default admin user with fixed password
3. **No TLS encryption**: Internal HTTP communication (acceptable if behind proxy)

## 📈 Monitoring

### Health Checks
- **Keycloak Endpoint**: `http://keycloak:8080/health/ready`
- **Interval**: 10s
- **Timeout**: 5s
- **Retries**: 5
- **Start Period**: 60s
- **Current Status**: Health check starting (authentication issues preventing startup)

### PostgreSQL Health Checks
- **Endpoint**: `pg_isready -U keycloak -d keycloak`
- **Interval**: 10s
- **Timeout**: 5s
- **Retries**: 5
- **Start Period**: 30s
- **Current Status**: Healthy

### Resource Limits
**Keycloak**:
- CPU Limit: 2 cores
- Memory Limit: 4GB
- CPU Reservation: 0.5 cores
- Memory Reservation: 1.25GB

**PostgreSQL**:
- CPU Limit: 2 cores
- Memory Limit: 2GB
- CPU Reservation: 0.5 cores
- Memory Reservation: 512MB

## 🚨 Current Issues

### 1. Database Authentication Failure
- **Problem**: Keycloak cannot authenticate to PostgreSQL database
- **Error**: `FATAL: password authentication failed for user "keycloak"`
- **Impact**: Service cannot start, authentication services unavailable
- **Investigation Status**: Database exists and manual connection works

### 2. Potential Causes
- **Environment Variable Mismatch**: Password in .env may not match PostgreSQL user
- **Container Network Issues**: Communication between keycloak and postgres containers
- **Startup Timing**: PostgreSQL may not be fully ready when Keycloak connects
- **Password Encoding**: Special characters in password may need escaping

## 🔄 Backup Strategy

### Data Backup
- **Method**: Manual PostgreSQL dumps recommended
- **Frequency**: Should be daily
- **Location**: Not currently configured
- **Command**: `docker exec postgres pg_dump -U keycloak keycloak > keycloak_backup.sql`

### Configuration Backup
- **Keycloak Data**: Stored in `./keycloak_data` volume
- **PostgreSQL Data**: Stored in `./postgres_data` volume
- **Environment**: Partially backed up (excluding sensitive data)

## 🚨 Troubleshooting

### Common Issues

1. **Database Authentication Failure**
   - **Symptoms**: Keycloak container restarting, authentication errors in logs
   - **Investigation**:
     - Verify database connectivity: `docker exec postgres psql -U keycloak -d keycloak -c '\l'`
     - Check password match between .env and PostgreSQL
   - **Solution**: Reset database password or update environment variable

2. **Service Startup Failure**
   - **Symptoms**: Container in "health: starting" state for extended time
   - **Investigation**: Check container logs: `docker logs keycloak`
   - **Solution**: Fix database connectivity issues first

3. **Network Connectivity Issues**
   - **Symptoms**: Cannot reach service from external URL
   - **Investigation**: Check nginx proxy configuration
   - **Solution**: Verify reverse proxy setup and DNS resolution

### Log Locations
- **Keycloak logs**: `docker logs keycloak`
- **PostgreSQL logs**: `docker logs postgres`
- **Health check logs**: Available in container logs

### Recovery Procedures
1. **Fix database authentication**:
   ```bash
   cd /nfs/dockermaster/docker/keycloak
   docker exec postgres psql -U keycloak -d keycloak -c "ALTER USER keycloak PASSWORD 'pera6Cantar';"
   docker compose restart keycloak
   ```

2. **Reset admin password**:
   ```bash
   # After service is running
   docker exec keycloak /opt/keycloak/bin/kc.sh export --users realm_file
   ```

3. **Complete rebuild**:
   ```bash
   docker compose down
   docker compose up -d
   ```

## 📝 Maintenance

### Critical Actions Needed
1. **Fix database authentication**: Resolve password mismatch issue
2. **Migrate secrets to Vault**: Remove passwords from environment files
3. **Configure backup strategy**: Implement automated database backups
4. **SSL/TLS setup**: Configure proper certificate management
5. **Monitoring integration**: Add Keycloak metrics to Prometheus

### Updates
- **Current Version**: Keycloak 26.3
- **PostgreSQL Version**: 17
- **Update schedule**: Manual (Watchtower disabled)
- **Update procedure**: Test database compatibility, backup first

### Dependencies
- **Required services**: PostgreSQL database, docker-servers-net network
- **Required by**: All applications using SSO authentication
- **Integration points**: OAuth/OIDC clients, SAML applications

## 🔗 Related Links

- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Keycloak Docker Image](https://hub.docker.com/r/keycloak/keycloak)
- [PostgreSQL Docker Image](https://hub.docker.com/_/postgres)
- [Keycloak Admin Console](https://keycloak.d.lcamaral.com/admin) (when working)

## 📅 Change Log

| Date | Change | Author |
|------|---------|---------|
| 2025-08-27 | Initial deployment and configuration | System |
| 2025-08-28 | Database authentication issue identified | Documentation Specialist A |
| 2025-08-28 | Comprehensive service documentation | Documentation Specialist A |

## 🔧 Immediate Action Items

### High Priority Fixes

1. **Resolve Database Authentication**
   ```bash
   # Check current database password
   cd /nfs/dockermaster/docker/keycloak
   docker exec postgres psql -U keycloak -d keycloak -c "SELECT current_user;"

   # Reset password to match environment
   docker exec postgres psql -U postgres -c "ALTER USER keycloak PASSWORD 'pera6Cantar';"

   # Restart Keycloak
   docker compose restart keycloak
   ```

2. **Verify Network Connectivity**
   ```bash
   # Test connection from keycloak to postgres
   docker exec keycloak ping postgres
   docker exec keycloak telnet postgres 5432
   ```

3. **Monitor Startup Process**
   ```bash
   # Follow logs during startup
   docker logs -f keycloak

   # Check health status
   docker exec keycloak curl -f http://localhost:8080/health/ready
   ```

### Configuration Verification
```bash
# Environment variables should match:
KC_DB_PASSWORD=pera6Cantar  # From .env file
# PostgreSQL user password should match this value
```

---
*Template Version: 1.0*
*Last Updated: 2025-08-28*
*Service Status: Starting - Database Authentication Issue*
