# Calibre to Portainer Migration - Validation Checklist

**Migration Date**: `_______`  
**Performed by**: `_______`  
**Start Time**: `_______`  
**End Time**: `_______`  

## 🔍 Pre-Migration Validation

### Environment Checks

- [ ] Portainer accessible at <http://192.168.59.2:9000>
- [ ] Git repository accessible: <https://github.com/luiscamaral/home-lab-inventory>
- [ ] Current Calibre service running and accessible
- [ ] Current service ports responding (58080, 58083)
- [ ] Volume paths exist and are accessible:
  - [ ] `/data/docker-volumes/calibre-library`
  - [ ] `/data/docker-volumes/calibre-config`

### Backup Completion

- [ ] Current service stopped successfully
- [ ] Library data backed up to `/backup/calibre-migration-$(date +%Y%m%d)/calibre-library`
- [ ] Configuration backed up to `/backup/calibre-migration-$(date +%Y%m%d)/calibre-config`
- [ ] Docker-compose files backed up
- [ ] Backup integrity verified (file count and sizes match)

## 🚀 Migration Process Validation

### Portainer Configuration

- [ ] Successfully logged into Portainer UI
- [ ] New stack created with name: `calibre-library`
- [ ] Git repository configured correctly:
  - [ ] Repository URL: <https://github.com/luiscamaral/home-lab-inventory>
  - [ ] Branch: main
  - [ ] Compose path: dockermaster/Docker/compose/calibre-server/Docker-compose.portainer.yml
- [ ] Environment variables configured correctly:
  - [ ] CALIBRE_LIBRARY_PATH=/opt/calibre/library
  - [ ] CALIBRE_CONFIG_PATH=/opt/calibre/config
  - [ ] CALIBRE_WEB_PORT=58080
  - [ ] CALIBRE_SERVER_PORT=58083
  - [ ] TZ=America/New_York

### Stack Deployment

- [ ] Stack deployed without errors
- [ ] Stack status shows "active"
- [ ] All containers started successfully
- [ ] Container logs show no critical errors
- [ ] Volume mounts configured correctly

## ✅ Post-Migration Validation

### Service Accessibility

- [ ] Web UI accessible at <http://192.168.59.2:58080>
- [ ] Content server accessible at <http://192.168.59.2:58083>
- [ ] Service responds within acceptable time (< 5 seconds)
- [ ] No HTTP errors or timeouts

### Data Integrity

- [ ] Library displays correctly in web interface
- [ ] Book count matches pre-migration count: _____ books
- [ ] Sample books open and display correctly
- [ ] Book covers load properly
- [ ] Metadata displays correctly (author, title, description)
- [ ] Custom categories and tags preserved

### Functionality Testing

- [ ] Search functionality works
- [ ] Book filtering works
- [ ] Can browse by author, series, tags
- [ ] Book download functionality works
- [ ] Can upload new books (if applicable)
- [ ] User preferences preserved
- [ ] Reading progress maintained (if applicable)

### Performance Validation

- [ ] Page load times acceptable (< 10 seconds initial load)
- [ ] Memory usage within expected range: _____ MB
- [ ] CPU usage normal during operation: _____ %
- [ ] No significant performance degradation vs. pre-migration

### Technical Validation

- [ ] Container health checks passing
- [ ] Correct port mappings active:
  - [ ] 0.0.0.0:58080->8080/tcp
  - [ ] 0.0.0.0:58083->8083/tcp
- [ ] Volume mounts correct:
  - [ ] calibre-library volume mounted at /opt/calibre/library
  - [ ] calibre-config volume mounted at /opt/calibre/config
- [ ] Network connectivity functional
- [ ] DNS resolution working
- [ ] No port conflicts detected

## 🔄 Rollback Testing

### Rollback Preparation (Test Only)

- [ ] **DO NOT EXECUTE IN PRODUCTION** - Document rollback capability:
  - [ ] Know how to stop Portainer stack
  - [ ] Original Docker-compose.yml backed up and ready
  - [ ] Rollback commands documented and understood
  - [ ] Data restore procedure validated

### Monitoring and Alerting

- [ ] Portainer monitoring enabled for stack
- [ ] Container resource monitoring active
- [ ] Log retention configured appropriately
- [ ] Health checks configured (if available)
- [ ] Service monitoring alerts functional (if configured)

## 📊 Performance Baseline Recording

### Resource Usage

- **Memory Usage**: _____ MB (container) / _____ MB (system)
- **CPU Usage**: _____ % (container) / _____ % (system)
- **Disk I/O**: Read _____ MB/s / Write _____ MB/s
- **Network**: Inbound _____ MB/s / Outbound _____ MB/s

### Response Times

- **Home Page Load**: _____ seconds
- **Library Browse**: _____ seconds
- **Book Search**: _____ seconds
- **Book Download**: _____ seconds for _____ MB file
- **Book Upload**: _____ seconds for _____ MB file

### Service Health

- **Uptime**: _____ minutes/hours since deployment
- **Error Rate**: _____ errors per hour
- **Success Rate**: _____ % successful requests
- **Concurrent Users Supported**: _____ users tested

## 🔧 Troubleshooting Validation

### Common Issues Tested

- [ ] Verified what to do if stack fails to deploy
- [ ] Confirmed how to access container logs via Portainer
- [ ] Tested network connectivity troubleshooting commands
- [ ] Validated volume mount verification procedures
- [ ] Confirmed permission issue resolution steps

### Recovery Procedures

- [ ] Backup restoration tested (in test environment)
- [ ] Service restart procedures validated
- [ ] Emergency rollback steps confirmed
- [ ] Support escalation paths documented

## 📋 Final Checklist

### Migration Success Criteria Met

- [ ] All services running and accessible
- [ ] Data integrity confirmed
- [ ] Performance acceptable
- [ ] Monitoring functional
- [ ] Documentation complete
- [ ] Rollback plan ready
- [ ] Team notified of completion

### Post-Migration Tasks

- [ ] Remove old backup files after retention period
- [ ] Schedule regular health checks
- [ ] Plan next service migration (if applicable)
- [ ] Update run books and procedures
- [ ] Schedule migration review meeting

## 📝 Issues and Notes

### Issues Encountered

Issue 1: `_______`
Resolution: `_______`
Time Lost: ______ minutes

Issue 2: `_______`
Resolution: `_______`
Time Lost: ______ minutes

Issue 3: `_______`
Resolution: `_______`
Time Lost: ______ minutes

### Migration Notes

- `_______`
- `_______`
- `_______`

### Lessons Learned

- `_______`
- `_______`
- `_______`

### Recommendations for Next Migration

- `_______`
- `_______`
- `_______`

## ✅ Sign-off

**Migration Completed Successfully**: [ ] Yes [ ] No

**Technical Lead Approval**: `_______` Date: `_______`

**Service Owner Approval**: `_______` Date: `_______`

**Post-Migration Review Scheduled**: [ ] Yes Date: `_______`

---
**Total Migration Time**: _____ hours _____ minutes  
**Downtime Duration**: _____ hours _____ minutes  
**Success Rate**: _____ %
