# Docspell Service Documentation

## 📊 Service Overview

- **Service Name**: docspell
- **Category**: Document Management / OCR
- **Status**: Active
- **IP Address**: Host network (port 8486)
- **External URL**: http://docspell.home (port 8486)

## 🚀 Description

Docspell is a personal document organizer that helps manage digital documents. It provides automatic document processing, full-text search capabilities, tagging, and organization features. The system includes OCR (Optical Character Recognition) for scanned documents and integrates with Apache Solr for advanced search functionality.

## 🔧 Configuration

### Docker Compose Location
```
/nfs/dockermaster/docker/docspell/docker-compose.yml
```

### Service Architecture
The stack consists of four interconnected services:
- **restserver**: Main API and web interface (port 7880 → 8486)
- **joex**: Background job processor and document processing engine
- **docspell-db**: PostgreSQL database backend
- **docspell-solr**: Apache Solr for full-text search

### Environment Variables
- **Database Configuration**:
  - `POSTGRES_DB`: docspell
  - `POSTGRES_USER`: docspelluser
  - `POSTGRES_PASSWORD`: docspellpass
  - `DOCSPELL_SERVER_BACKEND_JDBC_URL`: jdbc:postgresql://docspell-db:5432/docspell

- **Security Settings**:
  - `DOCSPELL_SERVER_ADMIN__ENDPOINT_SECRET`: [Admin API secret]
  - `DOCSPELL_SERVER_AUTH_SERVER__SECRET`: [Authentication secret]
  - `DOCSPELL_SERVER_INTEGRATION__ENDPOINT_HTTP__HEADER_HEADER__VALUE`: superduperpassword123

- **Application Settings**:
  - `DOCSPELL_SERVER_BASE_URL`: http://docspell.home
  - `DOCSPELL_SERVER_BACKEND_SIGNUP_MODE`: open
  - `DOCSPELL_SERVER_BACKEND_SIGNUP_NEW__INVITE__PASSWORD`: Saturno#1220
  - `TZ`: America/Denver

### Volumes
- `./docspell_db`: PostgreSQL database data
- `./docspell_solr`: Solr search index data

### Network Configuration
- **Network**: Host network
- **Ports**:
  - External: 8486 (mapped to internal 7880)
  - Internal services communicate via container names

## 🔐 Security

### Secrets Management
- Admin endpoint protected by secret key
- Authentication server with dedicated secret
- Integration endpoint with HTTP header authentication
- Database credentials configured

### Access Control
- **Signup mode**: Open registration enabled
- **New invite password**: Saturno#1220
- **Integration access**: HTTP header authentication
- **User management**: Available through web interface

## 📈 Monitoring

### Health Checks
- **PostgreSQL Database**:
  - Command: pg_isready check
  - Interval: 10s, Timeout: 45s, Retries: 10
- **Solr Search**:
  - Command: curl health check on admin/ping endpoint
  - Interval: 45s, Timeout: 10s, Start period: 30s

### Metrics
- **Full-text search**: Enabled via Solr integration
- **Application monitoring**: Through web interface

## 🔄 Backup Strategy

### Data Backup
- **Database**: Volume backup of `./docspell_db` directory
- **Search index**: Volume backup of `./docspell_solr` directory
- **Document storage**: Managed within application volumes

### Configuration Backup
- **Git repository**: Yes - docker-compose.yml included in dockermaster repo
- **Environment**: Embedded in compose file

## 🚨 Troubleshooting

### Common Issues
1. **Issue**: Full-text search not working
   - **Symptoms**: Search returns no results
   - **Solution**: Check Solr service health and connectivity

2. **Issue**: Document processing stuck
   - **Symptoms**: Documents not being processed
   - **Solution**: Check joex container logs and restart if needed

3. **Issue**: Database connection failures
   - **Symptoms**: Service startup failures
   - **Solution**: Verify PostgreSQL health and credentials

### Log Locations
- **Container logs**: 
  - `docker logs Docspell-RESTSERVER`
  - `docker logs Docspell-JOEX`
  - `docker logs Docspell-DB`
  - `docker logs Docspell-SOLR`

### Recovery Procedures
1. **Service restart**: `docker compose restart <service>`
2. **Full rebuild**: `docker compose down && docker compose up -d`
3. **Database recovery**: Restore from `./docspell_db` backup
4. **Search index recovery**: Restore from `./docspell_solr` backup

## 📝 Maintenance

### Updates
- **Update schedule**: Manual updates (Watchtower disabled)
- **Update procedure**: 
  1. Stop services
  2. Pull new images
  3. Restart stack
  4. Verify functionality

### Dependencies
- **Service startup order**: 
  1. docspell-db, docspell-solr
  2. restserver, joex
- **Required by**: Document processing workflows

### Resource Limits
Each service has:
- **CPU Limits**: 2 cores maximum
- **Memory Limits**: 4GB maximum  
- **CPU Reservations**: 0.5 cores minimum
- **Memory Reservations**: 512MB minimum

## 🔧 Features

### Document Processing
- **OCR**: Optical Character Recognition for scanned documents
- **Full-text search**: Powered by Apache Solr
- **Automatic tagging**: Based on document content
- **Document organization**: Folders, tags, and metadata

### Integration
- **API endpoints**: RESTful API for automation
- **HTTP integration**: Header-based authentication for uploads
- **Addon support**: Disabled by default

### Conversion Options
- **HTML converter**: WeasyPrint for HTML to PDF conversion
- **Document formats**: Multiple input format support

## 🔗 Related Links

- [Docspell Official Documentation](https://docspell.org/)
- [Docspell GitHub Repository](https://github.com/eikek/docspell)
- [Docspell Docker Hub](https://hub.docker.com/u/docspell)
- [Apache Solr Documentation](https://solr.apache.org/)

## 📅 Change Log

| Date | Change | Author |
|------|---------|---------|
| 2025-08-28 | Initial documentation | Documentation Team |

---
*Template Version: 1.0*
*Last Updated: 2025-08-28*