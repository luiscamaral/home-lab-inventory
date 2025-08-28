# Tactical Implementation Plan - Dockermaster Infrastructure Recovery

## Agent Coordination Strategy

### Recommended Agent Types

- **Git Recovery Specialist**: Tasks 1.x (repository conflict resolution)
- **Infrastructure Specialist**: Tasks 2.x (cleanup and optimization)
- **Documentation Team Lead**: Tasks 3.1-3.3 (coordination and templates)
- **Documentation Specialist A**: Tasks 3.4-3.6 (high priority services)
- **Documentation Specialist B**: Tasks 3.7-3.9 (medium/low priority services)
- **Security Engineer**: Tasks 4.x (Vault configuration and secrets)
- **DevOps Engineer**: Tasks 5.x (Portainer GitOps setup)
- **CI/CD Engineer**: Tasks 6.x (pipeline automation)
- **Quality Assurance**: Tasks 7.x (validation and testing)

### Parallel Execution Groups

- **Group A** [SEQUENTIAL]: Tasks 1.1-1.7 (must complete first)
- **Group B** [PARALLEL]: Tasks 2.1-2.5, 3.1-3.3
- **Group C** [PARALLEL]: Tasks 3.4-3.9 (after 3.3 completes)
- **Group D** [PARALLEL]: Tasks 4.1-4.3, 5.1-5.2
- **Group E** [DEPENDS ON: D]: Tasks 4.4-4.8, 5.3-5.7
- **Group F** [DEPENDS ON: B, E]: Tasks 6.x
- **Group G** [FINAL]: Tasks 7.x (validation after all complete)

## Relevant Files

### Core Implementation
- `/nfs/dockermaster/docker/` - Live service directories
- `/nfs/dockermaster/docker/compose/` - Deployment configurations
- `inventory/` - Local repository root
- `docs/` - Project documentation

### Service Documentation
- `dockermaster/services/<service_name>/README.md` - Service documentation
- `dockermaster/services/<service_name>/docker-compose.yml` - Service configuration
- `inventory/docker-containers.md` - Container inventory

### Configuration Files
- `.github/workflows/` - CI/CD pipeline definitions
- `dockermaster/.gitignore` - Repository exclusions
- `vault/config/` - Vault configuration files
- `portainer/stacks/` - Portainer stack definitions

### Scripts and Automation
- `scripts/deploy.sh` - Deployment automation
- `scripts/backup.sh` - Backup procedures
- `scripts/validate.sh` - Service validation

## Tasks

### Phase 1: Git Recovery and Conflict Resolution

- [x] 1.0 **Repository Conflict Resolution** [Git Recovery Specialist] ✅ COMPLETED
  - [x] 1.1 Analyze current git status and conflict details
    - SSH to dockermaster: `ssh dockermaster`
    - Check status: `cd /path/to/inventory && git status`
    - List conflicts: `git diff --name-only --diff-filter=U`
    - Document conflict files and nature

  - [x] 1.2 Backup critical documentation [BLOCKS: 1.3]
    - Create backup directory: `mkdir -p ~/backup/dockermaster-$(date +%Y%m%d)`
    - Backup docs: `cp -r docs/dockermaster-sync-report.md ~/backup/`
    - Backup CLAUDE.md: `cp CLAUDE.md ~/backup/`
    - Backup any work in progress: `git stash save "Pre-recovery backup"`

  - [x] 1.3 Abort current rebase operation [DEPENDS ON: 1.2]
    - Abort rebase: `git rebase --abort`
    - Verify clean state: `git status`
    - Check branch: `git branch -v`

  - [x] 1.4 Fetch and analyze remote state [PARALLEL]
    - Fetch latest: `git fetch origin --all`
    - Check remote branches: `git branch -r -v`
    - Compare with local: `git log --oneline --graph --all --decorate -20`
    - Identify PR #3 changes: `git show origin/main --name-only`

  - [x] 1.5 Reset to stable state [DEPENDS ON: 1.3, 1.4]
    - Create safety branch: `git branch backup-$(date +%Y%m%d) HEAD`
    - Reset to origin: `git reset --hard origin/dockermaster-config`
    - Verify state: `git status && git log --oneline -5`

  - [x] 1.6 Reapply preserved documentation [DEPENDS ON: 1.5]
    - Copy back docs: `cp ~/backup/dockermaster-*/docs/* docs/`
    - Restore CLAUDE.md updates: `cp ~/backup/dockermaster-*/CLAUDE.md .`
    - Stage changes: `git add docs/ CLAUDE.md`
    - Commit: `git commit -m "feat: restore documentation improvements from backup"`

  - [x] 1.7 Synchronize with remote [DEPENDS ON: 1.6]
    - Push changes: `git push origin dockermaster-config`
    - Verify sync: `git fetch && git status`
    - Create clean working branch: `git checkout -b dockermaster-recovery`
    - Success criteria: Clean git status, no conflicts
    - **Completion Note**: Branch created and pushed successfully, repository synchronized

### Phase 2: Repository Cleanup and Optimization

- [ ] 2.0 **Repository Structure Optimization** [Infrastructure Specialist]
  - [ ] 2.1 Analyze repository size and structure [PARALLEL]
    - Check size: `du -sh ./* | sort -h`
    - Identify large directories: `find . -type d -exec du -sh {} \; | sort -h | tail -20`
    - Check for dockermaster-live: `ls -la dockermaster-live/ 2>/dev/null`
    - Document findings in `docs/cleanup-report.md`

  - [ ] 2.2 Remove unnecessary sync directories [PARALLEL]
    - Remove dockermaster-live: `rm -rf dockermaster-live/`
    - Remove .history if exists: `rm -rf .history/`
    - Clean git cache: `git rm -r --cached dockermaster-live/ 2>/dev/null`
    - Verify removal: `ls -la && git status`

  - [ ] 2.3 Update .gitignore configuration [DEPENDS ON: 2.2]
    - Edit .gitignore: Add entries for:
      ```
      dockermaster-live/
      .history/
      *.swp
      .DS_Store
      .env.local
      ```
    - Stage changes: `git add .gitignore`
    - Commit: `git commit -m "chore: update .gitignore to exclude sync and temp directories"`

  - [ ] 2.4 Create documentation templates [PARALLEL]
    - Create template: `dockermaster/templates/service-template.md`
    - Include sections: Overview, Configuration, Dependencies, Secrets, Deployment, Health Checks
    - Create inventory template: `dockermaster/templates/inventory-template.md`
    - Commit templates: `git add dockermaster/templates/ && git commit -m "docs: add service documentation templates"`

  - [ ] 2.5 Establish directory structure [PARALLEL]
    - Create service directories: `mkdir -p dockermaster/services/{high-priority,medium-priority,low-priority}`
    - Create scripts directory: `mkdir -p scripts/{deployment,backup,validation}`
    - Create config directory: `mkdir -p config/{vault,portainer,github}`
    - Stage structure: `git add . && git commit -m "feat: establish organized directory structure"`

### Phase 3: Comprehensive Service Documentation

- [ ] 3.0 **Service Documentation Campaign** [Documentation Team Lead]
  - [ ] 3.1 Initialize documentation framework [PARALLEL]
    - Create service inventory matrix in `docs/service-matrix.md`
    - List all 32 services with current documentation status
    - Categorize by priority (High: 4, Medium: 1, Low: 10, Special: 5)
    - Create tracking spreadsheet for progress

  - [ ] 3.2 Set up SSH session management [PARALLEL]
    - Configure SSH multiplexing: `ssh -M -S /tmp/dockermaster-socket dockermaster`
    - Create helper script: `scripts/ssh-dockermaster.sh`
    - Test connection persistence: `ssh -S /tmp/dockermaster-socket dockermaster 'echo connected'`

  - [ ] 3.3 Create documentation automation tools [PARALLEL]
    - Script to extract compose configs: `scripts/extract-compose.sh`
    - Script to parse environment variables: `scripts/parse-env.sh`
    - Script to identify dependencies: `scripts/find-deps.sh`
    - Test scripts on known service: `./scripts/extract-compose.sh nginx`

- [ ] 3.0.1 **High Priority Service Documentation** [Documentation Specialist A]
  - [ ] 3.4 Document github-runner service [DEPENDS ON: 3.3]
    - SSH to dockermaster and navigate: `cd /nfs/dockermaster/docker/github-runner/`
    - Extract configuration: `cat docker-compose.yml`
    - Document environment variables and secrets
    - Identify dependencies and network requirements
    - Create: `dockermaster/services/high-priority/github-runner/README.md`
    - Include: Setup instructions, token management, workflow integration

  - [ ] 3.5 Document vault service [PARALLEL]
    - Navigate to vault: `cd /nfs/dockermaster/docker/vault/`
    - Document current unhealthy state and root causes
    - Extract configuration: Storage backend, seal configuration, policies
    - Document initialization procedure and unseal process
    - Create: `dockermaster/services/high-priority/vault/README.md`
    - Include recovery procedures for unhealthy state

  - [ ] 3.6 Document keycloak and prometheus services [PARALLEL]
    - Keycloak configuration at `/nfs/dockermaster/docker/keycloak/`
    - Document realms, clients, and authentication flows
    - Prometheus at `/nfs/dockermaster/docker/prometheus/`
    - Document scrape configs, alert rules, and targets
    - Create documentation for each in high-priority directory

- [ ] 3.0.2 **Medium and Low Priority Service Documentation** [Documentation Specialist B]
  - [ ] 3.7 Document rabbitmq service [DEPENDS ON: 3.3]
    - Navigate: `cd /nfs/dockermaster/docker/rabbitmq/`
    - Document queues, exchanges, and bindings
    - Extract user configurations and permissions
    - Create: `dockermaster/services/medium-priority/rabbitmq/README.md`

  - [ ] 3.8 Document low priority services batch 1 [PARALLEL]
    - Services: ansible-stack, bitwarden, docspell, fluentd, ghost.io
    - For each service:
      - Extract docker-compose.yml
      - Document ports, volumes, environment
      - Identify external dependencies
      - Create README in low-priority directory

  - [ ] 3.9 Document low priority services batch 2 [PARALLEL]
    - Services: kafka, mongodb, opentelemetry-home, otel, solr
    - Follow same documentation process
    - Note special configurations and clustering setups
    - Document data persistence requirements

### Phase 4: Vault Configuration and Secret Migration

- [ ] 4.0 **Vault Service Recovery and Configuration** [Security Engineer]
  - [ ] 4.1 Diagnose Vault health issues [PARALLEL]
    - Check container status: `docker ps -a | grep vault`
    - Review logs: `docker logs vault --tail 100`
    - Test API endpoint: `curl -k https://192.168.59.25:8200/v1/sys/health`
    - Document issues in `docs/vault-diagnosis.md`

  - [ ] 4.2 Backup existing Vault data [PARALLEL]
    - Create backup: `docker exec vault vault operator raft snapshot save /vault/data/backup-$(date +%Y%m%d).snap`
    - Copy locally: `docker cp vault:/vault/data/backup*.snap ./backups/`
    - Verify backup integrity

  - [ ] 4.3 Repair Vault configuration [DEPENDS ON: 4.1, 4.2]
    - Update docker-compose.yml with correct settings
    - Ensure proper volume mounts for data persistence
    - Configure environment variables for auto-unseal
    - Restart container: `docker-compose down && docker-compose up -d`
    - **USER INTERACTION REQUIRED**: Initialize Vault if needed

  - [ ] 4.4 Initialize Vault policies [DEPENDS ON: 4.3, BLOCKS: 4.5]
    - Create service policy template: `vault/policies/service-template.hcl`
    - Define paths: `secret/dockermaster/<service>/*`
    - Create admin policy: Full access to secret/dockermaster/
    - Create reader policy: Read-only access
    - Apply policies: `vault policy write <name> <file>`

  - [ ] 4.5 Create secret structure [DEPENDS ON: 4.4]
    - Create secret paths for each service:
      ```bash
      vault secrets enable -path=secret/dockermaster kv-v2
      ```
    - Organize by service: `secret/dockermaster/<service_name>/`
    - Create infrastructure secrets: `secret/infrastructure/`

  - [ ] 4.6 Extract existing secrets from services [PARALLEL]
    - Script to scan docker-compose files: `scripts/extract-secrets.sh`
    - Identify all environment variables with sensitive data
    - Create migration checklist in `docs/secret-migration.md`
    - Categorize by service and priority

  - [ ] 4.7 Migrate secrets to Vault [DEPENDS ON: 4.5, 4.6]
    - For each service, migrate secrets:
      ```bash
      vault kv put secret/dockermaster/<service>/database \
        username=<user> password=<pass> host=<host>
      ```
    - Document secret paths in service README
    - Create secret rotation schedule

  - [ ] 4.8 Configure service authentication [DEPENDS ON: 4.7]
    - Create service tokens for each application
    - Configure AppRole authentication for services
    - Test secret retrieval: `vault kv get secret/dockermaster/<service>/database`
    - Document authentication methods

### Phase 5: Portainer GitOps Configuration

- [ ] 5.0 **Portainer GitOps Integration** [DevOps Engineer]
  - [ ] 5.1 Access and assess Portainer [PARALLEL]
    - Access UI: `https://192.168.59.2:9000`
    - Check current version and settings
    - Review existing stacks and deployments
    - Document current configuration

  - [ ] 5.2 Backup Portainer configuration [PARALLEL]
    - Export settings via API:
      ```bash
      curl -X GET https://192.168.59.2:9000/api/backup \
        -H "Authorization: Bearer <token>" > portainer-backup.tar.gz
      ```
    - Backup stack definitions
    - Export environment configurations

  - [ ] 5.3 Configure Git repository integration [DEPENDS ON: 5.1]
    - Add repository in Portainer settings
    - Configure authentication with GitHub token
    - Set repository path: `github.com/<org>/inventory`
    - Test connection and pull

  - [ ] 5.4 Create webhook endpoints [DEPENDS ON: 5.3]
    - Generate webhook URL for each stack
    - Format: `https://192.168.59.2:9000/api/webhooks/<id>`
    - Document webhook URLs in `config/portainer/webhooks.md`
    - Configure webhook secret for security

  - [ ] 5.5 Configure GitHub webhooks [DEPENDS ON: 5.4]
    - Access repository settings on GitHub
    - Add webhook for push events to main branch
    - Set payload URL to Portainer webhook
    - Configure secret and content type (application/json)
    - Test webhook delivery

  - [ ] 5.6 Create stack templates [PARALLEL]
    - Create template for single-service deployment
    - Create template for multi-service stack
    - Include Vault integration for secrets
    - Store in `portainer/templates/`

  - [ ] 5.7 Test GitOps workflow [DEPENDS ON: 5.5, 5.6]
    - Make test change to non-critical service
    - Push to main branch
    - Verify webhook triggers
    - Confirm automatic deployment
    - Document workflow in `docs/gitops-guide.md`

### Phase 6: CI/CD Pipeline Enhancement

- [ ] 6.0 **CI/CD Pipeline Development** [CI/CD Engineer]
  - [ ] 6.1 Analyze existing GitHub runner setup [PARALLEL]
    - Review runner configuration at `/nfs/dockermaster/docker/github-runner/`
    - Check runner status: `docker exec github-runner ./config.sh --check`
    - Review current workflows in `.github/workflows/`
    - Document capabilities and limitations

  - [ ] 6.2 Design comprehensive pipeline architecture [PARALLEL]
    - Create pipeline stages: Validate → Test → Build → Deploy → Verify
    - Define stage triggers and conditions
    - Plan parallel execution strategies
    - Document in `docs/pipeline-architecture.md`

  - [ ] 6.3 Create validation stage workflows [DEPENDS ON: 6.2]
    - YAML validation: `.github/workflows/validate-yaml.yml`
    - Docker Compose validation workflow
    - Secret reference validation (ensure Vault paths exist)
    - Syntax checking for all configuration files

  - [ ] 6.4 Implement testing workflows [DEPENDS ON: 6.2]
    - Container security scanning: Trivy or similar
    - Configuration testing with test data
    - Network connectivity validation
    - Create: `.github/workflows/test-services.yml`

  - [ ] 6.5 Build deployment workflows [DEPENDS ON: 6.3, 6.4]
    - Main deployment workflow: `.github/workflows/deploy.yml`
    - Service-specific deployment jobs
    - Rollback workflow for failures
    - Blue-green deployment support

  - [ ] 6.6 Add monitoring and alerting [PARALLEL]
    - Health check jobs post-deployment
    - Slack/email notifications for failures
    - Deployment metrics collection
    - Success rate tracking

  - [ ] 6.7 Create manual trigger workflows [DEPENDS ON: 6.5]
    - Manual deployment workflow with service selection
    - Emergency rollback workflow
    - Vault secret rotation workflow
    - Backup trigger workflow

  - [ ] 6.8 Document CI/CD procedures [DEPENDS ON: 6.7]
    - Create runbook: `docs/cicd-runbook.md`
    - Document each workflow purpose and usage
    - Include troubleshooting guide
    - Add examples for common scenarios

### Phase 7: Validation and Quality Assurance

- [ ] 7.0 **System Validation and Testing** [Quality Assurance]
  - [ ] 7.1 Validate git repository state [SEQUENTIAL]
    - Confirm clean status: `git status`
    - Verify all branches synchronized
    - Check file permissions and ownership
    - Ensure .gitignore properly configured

  - [ ] 7.2 Verify service documentation completeness [DEPENDS ON: 3.9]
    - Check all 32 services have documentation
    - Validate documentation against template
    - Ensure all required sections present
    - Create coverage report: `docs/documentation-coverage.md`

  - [ ] 7.3 Test Vault integration [DEPENDS ON: 4.8]
    - Verify Vault health: `vault status`
    - Test secret retrieval for each service
    - Validate authentication methods work
    - Check audit logging enabled

  - [ ] 7.4 Validate GitOps workflow [DEPENDS ON: 5.7]
    - Test deployment for 3 different services
    - Verify webhook reliability
    - Test rollback procedures
    - Measure deployment times

  - [ ] 7.5 Test complete CI/CD pipeline [DEPENDS ON: 6.8]
    - Trigger full pipeline for test service
    - Verify all stages execute correctly
    - Test failure scenarios and rollbacks
    - Validate notifications work

  - [ ] 7.6 Performance validation [PARALLEL]
    - Measure deployment time (target: <6 minutes)
    - Check service startup times
    - Verify resource utilization
    - Document in `docs/performance-report.md`

  - [ ] 7.7 Security audit [PARALLEL]
    - Verify no secrets in repository
    - Check Vault policies are restrictive
    - Validate network segmentation
    - Review container security settings

  - [ ] 7.8 Create handover documentation [DEPENDS ON: 7.1-7.7]
    - Compile operational runbook
    - Create troubleshooting guide
    - Document common procedures
    - Prepare training materials

## Success Metrics

- ✅ All git conflicts resolved and repository clean
- ✅ 100% of services (32/32) documented
- ✅ Vault operational and all secrets migrated
- ✅ GitOps workflow functional with automatic deployments
- ✅ Complete CI/CD pipeline operational
- ✅ Deployment time <6 minutes achieved
- ✅ Zero service disruption during implementation

## Risk Mitigation

- **Git conflicts**: Complete backup before any operations
- **Service disruption**: Work on copies, test thoroughly before applying
- **Vault failure**: Maintain parallel secret storage during transition
- **Network issues**: No network changes, document current state first
- **Automation failures**: Manual fallback procedures documented

## Critical Dependencies

1. **Sequential Requirements**:
   - Git recovery MUST complete before any other work
   - Vault MUST be healthy before secret migration
   - Documentation templates MUST exist before service documentation

2. **User Interaction Points**:
   - Vault initialization (Phase 4.3)
   - GitHub webhook configuration (Phase 5.5)
   - Final validation sign-off (Phase 7.8)

3. **External Dependencies**:
   - GitHub API availability
   - Docker Hub for image pulls
   - DNS resolution (192.168.48.1)
   - NFS storage accessibility

## Project Standards Integration

- Follow `.yamllint.yml` for YAML validation
- Apply `.markdownlint.json` for documentation
- Use existing CI/CD patterns from `.github/workflows/`
- Integrate with current Docker configurations
- Maintain compatibility with mise tool management

## Agent Handoff Protocol

1. Each agent receives specific task group
2. Agents work independently within their scope
3. Clear success criteria for task completion
4. Documentation of any blockers or issues
5. Handoff includes summary of completed work
6. Next agent picks up from validated checkpoint

## Execution Notes

- Each task has specific commands and validation steps
- Parallel tasks can be distributed to multiple agents
- Dependencies clearly marked to prevent conflicts
- User interaction points explicitly noted
- All changes must be committed and pushed after validation
- Documentation is generated alongside implementation
- Testing occurs at each phase boundary
