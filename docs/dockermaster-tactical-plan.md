# 🎯 Dockermaster Recovery - Tactical Execution Plan

**Project:** Dockermaster Infrastructure Recovery  
**Duration:** 34 hours over 5-7 days  
**Start Date:** TBD  
**Project Manager:** System Administrator

## 📊 Executive Dashboard

| Phase | Duration | Status | Priority | Dependencies |
|-------|----------|--------|----------|--------------|
| 1. Git Recovery | 2h | 🔴 Not Started | CRITICAL | None |
| 2. Repo Cleanup | 4h | 🔴 Not Started | HIGH | Phase 1 |
| 3. Documentation | 12h | 🔴 Not Started | HIGH | Phase 2 |
| 4. Vault Setup | 6h | 🔴 Not Started | CRITICAL | User Input |
| 5. GitOps Config | 4h | 🔴 Not Started | MEDIUM | Phase 4 |
| 6. CI/CD Pipeline | 6h | 🔴 Not Started | MEDIUM | Phase 5 |

## 🚨 Phase 1: Git Recovery (2 hours) - CRITICAL PATH

### 1.1 Initial Assessment (15 min)
```bash
# Commands to execute
cd ~/Library/CloudStorage/SynologyDrive-lamaral/SynDrive/05.Code/Dev/lamaral/home/inventory
git status
git log --oneline -10
git branch -a
git diff HEAD
```

**Success Criteria:**
- ✅ Current branch identified
- ✅ Conflict files listed
- ✅ Remote branch status confirmed

### 1.2 Backup Critical Files (30 min)
```bash
# Create backup directory
mkdir -p ~/backup/dockermaster-$(date +%Y%m%d)
cd ~/backup/dockermaster-$(date +%Y%m%d)

# Backup critical files
cp -r ~/Library/CloudStorage/SynologyDrive-lamaral/SynDrive/05.Code/Dev/lamaral/home/inventory/docs .
cp ~/Library/CloudStorage/SynologyDrive-lamaral/SynDrive/05.Code/Dev/lamaral/home/inventory/CLAUDE.md .
cp ~/Library/CloudStorage/SynologyDrive-lamaral/SynDrive/05.Code/Dev/lamaral/home/inventory/.gitignore .

# Create tar archive
tar -czf dockermaster-backup-$(date +%Y%m%d-%H%M%S).tar.gz *
```

**Files to Preserve:**
- `docs/dockermaster-sync-report.md`
- `CLAUDE.md` (updated service notes)
- `.gitignore` (with new exclusions)

### 1.3 Resolve Git Conflicts (45 min)
```bash
# Option A: If in rebase
git rebase --abort

# Option B: If in merge
git merge --abort

# Reset to clean state
git fetch origin
git reset --hard origin/main

# Create new working branch
git checkout -b dockermaster-recovery-$(date +%Y%m%d)

# Reapply backed up changes
cp ~/backup/dockermaster-$(date +%Y%m%d)/docs/* ./docs/
cp ~/backup/dockermaster-$(date +%Y%m%d)/CLAUDE.md .
cp ~/backup/dockermaster-$(date +%Y%m%d)/.gitignore .

# Commit preserved changes
git add .
git commit -m "fix: preserve documentation from conflict resolution

- Restored dockermaster-sync-report.md
- Updated CLAUDE.md with service notes
- Enhanced .gitignore exclusions"
```

### 1.4 Validate Resolution (30 min)
```bash
# Verify clean state
git status
git diff origin/main
git log --oneline -5

# Push to remote
git push -u origin dockermaster-recovery-$(date +%Y%m%d)
```

**Validation Checklist:**
- [ ] No merge/rebase in progress
- [ ] Working tree clean
- [ ] All documentation preserved
- [ ] Branch pushed to remote

## 🧹 Phase 2: Repository Cleanup (4 hours)

### 2.1 Remove Unnecessary Directories (1 hour)
```bash
# Identify large directories
du -sh * | sort -h

# Remove synced dockermaster-live (700MB+)
rm -rf dockermaster-live/
rm -rf .history/

# Update .gitignore
cat >> .gitignore << 'EOF'

# Dockermaster sync exclusions
dockermaster-live/
.history/
*.backup
*.tmp
.DS_Store
EOF

git add .gitignore
git commit -m "chore: remove unnecessary sync directories

- Removed dockermaster-live/ (700MB)
- Removed .history/ directory
- Updated .gitignore exclusions"
```

### 2.2 Create Documentation Templates (1.5 hours)
```bash
# Create templates directory
mkdir -p docs/templates

# Service documentation template
cat > docs/templates/service-template.md << 'EOF'
# Service: [SERVICE_NAME]

## Overview
- **Purpose:** [Brief description]
- **Image:** [Docker image]
- **Version:** [Current version]
- **Status:** [Active/Inactive]
- **Priority:** [High/Medium/Low]

## Configuration

### Network
- **IP Address:** 192.168.59.x
- **Ports:** 
  - [port]: [description]

### Volumes
- `/path/on/host:/path/in/container` - [description]

### Environment Variables
| Variable | Description | Example |
|----------|-------------|---------|
| VAR_NAME | Description | value |

### Secrets (Vault)
- Path: `secret/dockermaster/[service_name]/`
- Keys:
  - `key_name`: [description]

## Dependencies
- [Service 1]: [Why needed]
- [Service 2]: [Why needed]

## Deployment

### Docker Compose
\`\`\`yaml
# Location: /nfs/dockermaster/docker/[service_name]/docker-compose.yml
version: '3.8'
services:
  [service]:
    image: [image]:[tag]
    ...
\`\`\`

### Health Check
\`\`\`bash
docker exec [container] [health_command]
\`\`\`

## Maintenance

### Backup
- **Frequency:** [Daily/Weekly]
- **Location:** `/backup/[service_name]/`
- **Retention:** [30 days]

### Logs
- **Location:** `/var/log/docker/[service_name]/`
- **Rotation:** [Daily/Weekly]

### Updates
1. Check for new version
2. Backup current configuration
3. Update docker-compose.yml
4. Deploy via Portainer

## Troubleshooting

### Common Issues
1. **Issue:** [Description]
   - **Solution:** [Steps to resolve]

### Recovery Procedures
1. Stop service: `docker compose down`
2. Restore backup: `[commands]`
3. Start service: `docker compose up -d`

## References
- [Official Documentation](url)
- [GitHub Repository](url)
EOF
```

### 2.3 Organize Repository Structure (1.5 hours)
```bash
# Create organized structure
mkdir -p inventory/services/{high-priority,medium-priority,low-priority,deprecated}
mkdir -p scripts/{deployment,maintenance,monitoring}
mkdir -p configs/vault-policies

# Move existing documentation
git mv inventory/*.md inventory/
git mv docs/dockermaster-sync-report.md docs/reports/

# Create index files
cat > inventory/services/README.md << 'EOF'
# Service Inventory

## Directory Structure
- `high-priority/` - Critical infrastructure services
- `medium-priority/` - Important but non-critical services  
- `low-priority/` - Optional or experimental services
- `deprecated/` - Services scheduled for removal

## Service Count
- **Total Services:** 32
- **Documented:** 12/32 (37.5%)
- **Undocumented:** 20/32 (62.5%)

## Quick Links
- [High Priority Services](high-priority/)
- [Medium Priority Services](medium-priority/)
- [Low Priority Services](low-priority/)
- [Deprecated Services](deprecated/)
EOF

git add -A
git commit -m "refactor: organize repository structure

- Created service priority directories
- Added documentation templates
- Organized scripts and configs"
```

## 📝 Phase 3: Service Documentation Sprint (12 hours)

### 3.1 High Priority Services (4 hours)

#### GitHub Runner Documentation
```bash
# SSH to dockermaster
ssh dockermaster

# Analyze service
cd /nfs/dockermaster/docker/github-runner
cat docker-compose.yml
docker ps -a | grep github-runner
docker logs github-runner-homelab --tail 50

# Document findings
exit
```

**Documentation Tasks:**
1. Create `inventory/services/high-priority/github-runner.md`
2. Document webhook configuration
3. Map environment variables
4. Note ACCESS_TOKEN location

#### Vault Service Documentation
```bash
ssh dockermaster
cd /nfs/dockermaster/docker/vault
docker inspect vault
docker logs vault --tail 100
# Check health status
curl -s http://192.168.59.25:8200/v1/sys/health | jq
exit
```

**Documentation Tasks:**
1. Create `inventory/services/high-priority/vault.md`
2. Document unhealthy status cause
3. List initialization requirements
4. Map storage backend config

#### Keycloak Service Documentation
```bash
ssh dockermaster
cd /nfs/dockermaster/docker/keycloak
docker compose ps
docker logs keycloak --tail 50
exit
```

**Documentation Tasks:**
1. Create `inventory/services/high-priority/keycloak.md`
2. Document PostgreSQL dependency
3. List realm configurations
4. Note integration points

#### Prometheus Documentation
```bash
ssh dockermaster
cd /nfs/dockermaster/docker/prometheus
ls -la
cat docker-compose.yml 2>/dev/null || echo "Not deployed"
exit
```

### 3.2 Medium Priority Services (2 hours)

#### RabbitMQ Documentation
```bash
ssh dockermaster
cd /nfs/dockermaster/docker/rabbitmq
docker ps -a | grep rabbitmq
docker logs rabbitmq --tail 100 2>/dev/null
exit
```

### 3.3 Low Priority Services (4 hours)

**Parallel Documentation Process:**
```bash
# Generate service list
ssh dockermaster "ls -1 /nfs/dockermaster/docker/" > services.txt

# For each service, create basic documentation
for service in ansible-stack bitwarden docspell fluentd ghost.io kafka mongodb opentelemetry-home otel solr; do
  echo "Documenting: $service"
  ssh dockermaster "cd /nfs/dockermaster/docker/$service && cat docker-compose.yml" > temp_$service.yml
done
```

### 3.4 Documentation Validation (2 hours)
```bash
# Count documented services
find inventory/services -name "*.md" | wc -l

# Validate documentation completeness
for file in inventory/services/*/*.md; do
  echo "Checking: $file"
  grep -q "Purpose:" "$file" || echo "  Missing: Purpose"
  grep -q "Image:" "$file" || echo "  Missing: Image"
  grep -q "Dependencies:" "$file" || echo "  Missing: Dependencies"
done
```

## 🔐 Phase 4: Vault Integration (6 hours) - REQUIRES USER

### 4.1 Fix Vault Health (2 hours)
```bash
# SSH to dockermaster
ssh dockermaster

# Check current status
docker logs vault --tail 200
docker exec vault vault status

# Restart with proper config
cd /nfs/dockermaster/docker/vault
docker compose down
docker compose up -d

# Wait for startup
sleep 10
curl -s http://192.168.59.25:8200/v1/sys/health
```

### 4.2 Initialize Vault (1 hour) - INTERACTIVE
```bash
# Initialize Vault (USER REQUIRED)
docker exec -it vault vault operator init \
  -key-shares=5 \
  -key-threshold=3

# IMPORTANT: Save the output securely!
# Unseal keys and root token will be displayed

# Unseal process (need 3 keys)
docker exec vault vault operator unseal [key1]
docker exec vault vault operator unseal [key2]
docker exec vault vault operator unseal [key3]

# Login with root token
docker exec vault vault login [root-token]
```

### 4.3 Configure Vault Policies (1.5 hours)
```bash
# Create service policies
cat > configs/vault-policies/dockermaster-services.hcl << 'EOF'
path "secret/data/dockermaster/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/dockermaster/*" {
  capabilities = ["list", "read"]
}
EOF

# Apply policy
docker exec vault vault policy write dockermaster-services /policies/dockermaster-services.hcl

# Create service authentication
docker exec vault vault auth enable userpass
docker exec vault vault write auth/userpass/users/github-runner \
  password=temp-password \
  policies=dockermaster-services
```

### 4.4 Migrate Secrets (1.5 hours)
```bash
# Extract current secrets from services
for service in github-runner keycloak rabbitmq; do
  echo "Migrating secrets for: $service"
  
  # Create in Vault
  docker exec vault vault kv put secret/dockermaster/$service \
    database_password=changeme \
    api_key=changeme
done

# Update docker-compose files to use Vault
# This will be done in Phase 5
```

## 🚀 Phase 5: Portainer GitOps Configuration (4 hours)

### 5.1 Configure Portainer Webhooks (1.5 hours)
```bash
# Access Portainer UI
echo "Open browser: http://192.168.59.2:9000"

# Via API (alternative)
curl -X POST http://192.168.59.2:9000/api/auth \
  -H "Content-Type: application/json" \
  -d '{"Username":"admin","Password":"[password]"}' \
  | jq -r '.jwt' > portainer-token.txt

TOKEN=$(cat portainer-token.txt)

# Create webhook for each stack
curl -X PUT "http://192.168.59.2:9000/api/stacks/1/webhook" \
  -H "Authorization: Bearer $TOKEN"
```

### 5.2 Create Stack Definitions (1.5 hours)
```bash
# For each service, create Portainer stack config
for service in github-runner vault keycloak prometheus; do
  cat > configs/portainer-stacks/$service.yml << EOF
name: $service
file: /nfs/dockermaster/docker/compose/$service/docker-compose.yml
env:
  - VAULT_ADDR=http://192.168.59.25:8200
  - VAULT_TOKEN=\${VAULT_TOKEN}
EOF
done
```

### 5.3 Test Deployment Pipeline (1 hour)
```bash
# Make test change
cd inventory
echo "# Test deployment" >> services/high-priority/github-runner.md
git add -A
git commit -m "test: validate GitOps deployment"
git push

# Monitor deployment
ssh dockermaster "docker ps --format 'table {{.Names}}\t{{.Status}}'"

# Verify webhook triggered
curl http://192.168.59.2:9000/api/webhooks/[webhook-id]/logs
```

## 🔧 Phase 6: CI/CD Pipeline Enhancement (6 hours)

### 6.1 Configure GitHub Actions (2 hours)
```bash
# Create workflow file
mkdir -p .github/workflows
cat > .github/workflows/deploy.yml << 'EOF'
name: Deploy to Dockermaster

on:
  push:
    branches: [main]
    paths:
      - 'dockermaster/docker/compose/**'
      - '.github/workflows/deploy.yml'

jobs:
  validate:
    runs-on: [self-hosted, linux]
    steps:
      - uses: actions/checkout@v4
      
      - name: Validate Docker Compose files
        run: |
          for compose in dockermaster/docker/compose/*/docker-compose.yml; do
            docker compose -f "$compose" config > /dev/null
          done
      
      - name: Security scan
        run: |
          # Add security scanning here
          echo "Security scan placeholder"

  deploy:
    needs: validate
    runs-on: [self-hosted, linux]
    steps:
      - name: Trigger Portainer deployment
        run: |
          curl -X POST http://192.168.59.2:9000/api/webhooks/${{ secrets.PORTAINER_WEBHOOK }}
      
      - name: Verify deployment
        run: |
          sleep 30
          # Add health checks
EOF

git add .github/workflows/deploy.yml
git commit -m "feat: add CI/CD deployment workflow"
```

### 6.2 Setup Monitoring (2 hours)
```bash
# Create monitoring script
cat > scripts/monitoring/health-check.sh << 'EOF'
#!/bin/bash
# Service health monitoring

SERVICES=(
  "github-runner-homelab"
  "vault"
  "keycloak"
  "portainer"
)

for service in "${SERVICES[@]}"; do
  if docker ps | grep -q "$service"; then
    echo "✅ $service: Running"
    docker exec "$service" echo "Health check" > /dev/null 2>&1 || echo "⚠️  $service: Unhealthy"
  else
    echo "❌ $service: Not running"
  fi
done
EOF

chmod +x scripts/monitoring/health-check.sh

# Add to cron
ssh dockermaster "crontab -l" > current-cron
echo "*/5 * * * * /nfs/dockermaster/docker/scripts/monitoring/health-check.sh" >> current-cron
ssh dockermaster "crontab" < current-cron
```

### 6.3 Create Rollback Procedures (2 hours)
```bash
# Rollback script
cat > scripts/deployment/rollback.sh << 'EOF'
#!/bin/bash
# Emergency rollback procedure

SERVICE=$1
BACKUP_VERSION=$2

if [ -z "$SERVICE" ] || [ -z "$BACKUP_VERSION" ]; then
  echo "Usage: $0 <service> <backup-version>"
  exit 1
fi

echo "Rolling back $SERVICE to $BACKUP_VERSION"

# Stop current service
docker compose -f /nfs/dockermaster/docker/$SERVICE/docker-compose.yml down

# Restore backup
cp /backup/$SERVICE/docker-compose.yml.$BACKUP_VERSION \
   /nfs/dockermaster/docker/$SERVICE/docker-compose.yml

# Start service
docker compose -f /nfs/dockermaster/docker/$SERVICE/docker-compose.yml up -d

# Verify
docker ps | grep $SERVICE
EOF

chmod +x scripts/deployment/rollback.sh
```

## 📋 Validation Checkpoints

### Phase 1 Validation
- [ ] Git status clean
- [ ] No conflicts present
- [ ] Documentation preserved
- [ ] Branch pushed to remote

### Phase 2 Validation
- [ ] Repository size reduced by 700MB+
- [ ] Templates created
- [ ] Structure organized
- [ ] .gitignore updated

### Phase 3 Validation
- [ ] 32/32 services documented
- [ ] All templates filled
- [ ] Dependencies mapped
- [ ] Vault paths defined

### Phase 4 Validation
- [ ] Vault service healthy
- [ ] Vault initialized and unsealed
- [ ] Policies configured
- [ ] Test secret retrieval successful

### Phase 5 Validation
- [ ] Webhooks configured
- [ ] Test deployment successful
- [ ] Stacks visible in Portainer
- [ ] Automated trigger working

### Phase 6 Validation
- [ ] GitHub Actions workflow runs
- [ ] Health checks operational
- [ ] Rollback tested
- [ ] Full pipeline execution < 6 minutes

## 🚦 Go/No-Go Decision Points

### After Phase 1
**Decision:** Continue only if git repository is clean
- ✅ **Go:** No conflicts, documentation preserved
- ❌ **No-Go:** Conflicts remain, data loss risk

### After Phase 3
**Decision:** Proceed to Vault only if documentation > 80%
- ✅ **Go:** Critical services documented
- ❌ **No-Go:** Insufficient documentation for automation

### After Phase 4
**Decision:** GitOps requires healthy Vault
- ✅ **Go:** Vault operational, secrets accessible
- ❌ **No-Go:** Vault unhealthy, manual secret management

## 📊 Success Metrics Tracking

| Metric | Baseline | Target | Current | Status |
|--------|----------|--------|---------|--------|
| Services Documented | 12/32 | 32/32 | - | 🔴 |
| Deployment Time | 30 min | 6 min | - | 🔴 |
| Secret Coverage | 0% | 100% | - | 🔴 |
| Pipeline Success | N/A | 95% | - | 🔴 |
| Service Uptime | 99% | 99.9% | - | 🟡 |

## 🎯 Daily Execution Schedule

### Day 1 (6 hours)
- **Morning (2h):** Phase 1 - Git Recovery
- **Afternoon (4h):** Phase 2 - Repository Cleanup

### Day 2 (6 hours)
- **All Day:** Phase 3 - Service Documentation (Part 1)

### Day 3 (6 hours)
- **All Day:** Phase 3 - Service Documentation (Part 2)

### Day 4 (6 hours)
- **All Day:** Phase 4 - Vault Integration (USER REQUIRED)

### Day 5 (6 hours)
- **Morning (4h):** Phase 5 - GitOps Configuration
- **Afternoon (2h):** Phase 6 - CI/CD Pipeline (Part 1)

### Day 6 (4 hours)
- **Morning (4h):** Phase 6 - CI/CD Pipeline (Part 2)

### Day 7 (Buffer)
- Final testing
- Documentation review
- Handover preparation

## 🆘 Emergency Procedures

### Git Recovery Failure
```bash
# If all else fails, clone fresh
cd ~/temp
git clone [repository-url] inventory-fresh
cp -r ~/backup/dockermaster-*/docs inventory-fresh/
cd inventory-fresh
git checkout -b emergency-recovery
git add -A
git commit -m "emergency: fresh clone with preserved docs"
git push -u origin emergency-recovery
```

### Vault Corruption
```bash
# Restore from backup
docker compose -f /nfs/dockermaster/docker/vault/docker-compose.yml down
cp /backup/vault/data/* /nfs/dockermaster/volumes/vault/
docker compose -f /nfs/dockermaster/docker/vault/docker-compose.yml up -d
```

### Service Outage
```bash
# Quick recovery
SERVICE=$1
docker restart $SERVICE || \
  docker compose -f /nfs/dockermaster/docker/$SERVICE/docker-compose.yml up -d --force-recreate
```

## 📞 Escalation Matrix

| Issue Type | First Response | Escalation | Timeline |
|------------|---------------|------------|----------|
| Git Conflicts | Try automated resolution | Manual merge | 30 min |
| Service Down | Auto-restart | Manual intervention | 5 min |
| Vault Failure | Unseal attempt | Restore backup | 15 min |
| Pipeline Failure | Retry | Manual deployment | 10 min |
| Network Issue | Verify config | System reboot | 20 min |

## ✅ Project Completion Checklist

### Documentation
- [ ] All 32 services documented
- [ ] Templates standardized
- [ ] Runbooks created
- [ ] Architecture diagrams updated

### Infrastructure
- [ ] Vault operational
- [ ] Secrets migrated
- [ ] GitOps configured
- [ ] Monitoring active

### Automation
- [ ] CI/CD pipeline functional
- [ ] Webhooks configured
- [ ] Health checks automated
- [ ] Rollback tested

### Knowledge Transfer
- [ ] User trained on Vault
- [ ] Documentation reviewed
- [ ] Emergency procedures tested
- [ ] Handover complete

---

**Last Updated:** 2025-08-28  
**Next Review:** After Phase 1 Completion  
**Contact:** System Administrator