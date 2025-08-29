#!/bin/bash
# Dockermaster Service Deployment Script
# This script provides robust service deployment with health checks and rollback capabilities

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_PATH="${DEPLOY_PATH:-/nfs/dockermaster/docker}"
VAULT_ADDR="${VAULT_ADDR:-http://vault.d.lcamaral.com}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
DEPLOYMENT_TIMEOUT="${DEPLOYMENT_TIMEOUT:-600}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-300}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS] SERVICE_NAME

Deploy a dockermaster service with comprehensive health checks and rollback capability.

ARGUMENTS:
    SERVICE_NAME    Name of the service to deploy (must exist in $DEPLOY_PATH)

OPTIONS:
    -h, --help                    Show this help message
    -v, --verbose                 Enable verbose output
    -n, --dry-run                 Show what would be deployed without executing
    -f, --force                   Force deployment even if health checks fail
    -s, --skip-backup             Skip pre-deployment backup creation
    -c, --skip-health-check       Skip post-deployment health checks
    -r, --skip-rollback           Disable automatic rollback on failure
    -t, --timeout SECONDS         Deployment timeout in seconds (default: $DEPLOYMENT_TIMEOUT)
    -w, --wait-timeout SECONDS    Health check timeout in seconds (default: $HEALTH_CHECK_TIMEOUT)
    --backup-id ID               Use specific backup ID for rollback reference
    --vault-token TOKEN          Vault authentication token
    --env-file FILE              Additional environment file to load

EXAMPLES:
    $0 vault                     # Deploy vault service
    $0 -v --dry-run portainer    # Show what would be deployed for portainer
    $0 -f --skip-health-check nginx-rproxy  # Force deploy nginx without health checks
    $0 --timeout 900 calibre-server         # Deploy with 15-minute timeout

ENVIRONMENT VARIABLES:
    DEPLOY_PATH                  Base path for service deployments
    VAULT_ADDR                   Vault server address
    LOG_LEVEL                    Logging level (DEBUG, INFO, WARN, ERROR)
    DEPLOYMENT_TIMEOUT           Default deployment timeout
    HEALTH_CHECK_TIMEOUT         Default health check timeout
    BACKUP_RETENTION_DAYS        Days to retain backups

EXIT CODES:
    0    Success
    1    General error
    2    Service not found
    3    Deployment failed
    4    Health check failed
    5    Rollback failed
    10   Invalid arguments
EOF
}

# Parse command line arguments
parse_args() {
    VERBOSE=false
    DRY_RUN=false
    FORCE=false
    SKIP_BACKUP=false
    SKIP_HEALTH_CHECK=false
    SKIP_ROLLBACK=false
    BACKUP_ID=""
    VAULT_TOKEN=""
    ENV_FILE=""
    SERVICE_NAME=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                LOG_LEVEL="DEBUG"
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -s|--skip-backup)
                SKIP_BACKUP=true
                shift
                ;;
            -c|--skip-health-check)
                SKIP_HEALTH_CHECK=true
                shift
                ;;
            -r|--skip-rollback)
                SKIP_ROLLBACK=true
                shift
                ;;
            -t|--timeout)
                DEPLOYMENT_TIMEOUT="$2"
                shift 2
                ;;
            -w|--wait-timeout)
                HEALTH_CHECK_TIMEOUT="$2"
                shift 2
                ;;
            --backup-id)
                BACKUP_ID="$2"
                shift 2
                ;;
            --vault-token)
                VAULT_TOKEN="$2"
                shift 2
                ;;
            --env-file)
                ENV_FILE="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                exit 10
                ;;
            *)
                if [[ -z "$SERVICE_NAME" ]]; then
                    SERVICE_NAME="$1"
                else
                    log_error "Multiple service names provided: $SERVICE_NAME and $1"
                    exit 10
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$SERVICE_NAME" ]]; then
        log_error "Service name is required"
        usage
        exit 10
    fi
}

# Validate environment and prerequisites
validate_environment() {
    log_info "Validating deployment environment..."

    # Check if running on correct host
    if [[ -n "${EXPECTED_HOST:-}" ]] && [[ "$(hostname)" != "$EXPECTED_HOST" ]]; then
        log_warn "Running on $(hostname), expected $EXPECTED_HOST"
    fi

    # Check Docker availability
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not available"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not accessible"
        exit 1
    fi

    # Check docker compose
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not available"
        exit 1
    fi

    # Check deployment directory
    if [[ ! -d "$DEPLOY_PATH" ]]; then
        log_error "Deployment path does not exist: $DEPLOY_PATH"
        exit 1
    fi

    # Check service directory
    SERVICE_DIR="$DEPLOY_PATH/$SERVICE_NAME"
    if [[ ! -d "$SERVICE_DIR" ]]; then
        log_error "Service directory does not exist: $SERVICE_DIR"
        exit 2
    fi

    # Check compose file
    COMPOSE_FILE=""
    if [[ -f "$SERVICE_DIR/docker-compose.yml" ]]; then
        COMPOSE_FILE="$SERVICE_DIR/docker-compose.yml"
    elif [[ -f "$SERVICE_DIR/docker-compose.yaml" ]]; then
        COMPOSE_FILE="$SERVICE_DIR/docker-compose.yaml"
    else
        log_error "No docker-compose file found in $SERVICE_DIR"
        exit 2
    fi

    # Validate compose file syntax
    cd "$SERVICE_DIR"
    if ! docker compose config &> /dev/null; then
        log_error "Invalid docker-compose configuration in $SERVICE_DIR"
        exit 2
    fi

    # Check disk space
    AVAILABLE_KB=$(df "$DEPLOY_PATH" | awk 'NR==2 {print $4}')
    if [[ $AVAILABLE_KB -lt 1048576 ]]; then  # Less than 1GB
        log_warn "Low disk space: ${AVAILABLE_KB}KB available"
    fi

    # Check network
    if ! docker network ls | grep -q docker-servers-net; then
        log_warn "docker-servers-net network not found"
    fi

    log_success "Environment validation completed"
}

# Load secrets from Vault or local environment
load_secrets() {
    log_info "Loading secrets for $SERVICE_NAME..."

    # Check if Vault is available
    VAULT_AVAILABLE=false
    if [[ -n "$VAULT_TOKEN" ]] && curl -s -f "$VAULT_ADDR/v1/sys/health" &> /dev/null; then
        VAULT_AVAILABLE=true
        export VAULT_TOKEN
        log_info "Vault is available for secret management"
    else
        log_warn "Vault not available, using local environment files"
    fi

    # Load additional environment file if specified
    if [[ -n "$ENV_FILE" ]] && [[ -f "$ENV_FILE" ]]; then
        log_info "Loading additional environment file: $ENV_FILE"
        # shellcheck source=/dev/null
        source "$ENV_FILE"
    fi

    # Load service-specific environment
    SERVICE_ENV="$SERVICE_DIR/.env"
    if [[ -f "$SERVICE_ENV" ]]; then
        log_info "Loading service environment file: $SERVICE_ENV"
        # Note: We don't source it directly for security, let docker-compose handle it
    else
        log_warn "No .env file found for $SERVICE_NAME"
    fi

    # TODO: Load secrets from Vault when available
    # if [[ "$VAULT_AVAILABLE" == "true" ]]; then
    #     vault kv get -format=json "secret/dockermaster/$SERVICE_NAME" > /tmp/secrets.json
    # fi
}

# Create backup of current state
create_backup() {
    if [[ "$SKIP_BACKUP" == "true" ]]; then
        log_info "Skipping backup creation (--skip-backup)"
        return 0
    fi

    log_info "Creating backup of current state..."

    local timestamp=$(date +%Y%m%d-%H%M%S)
    BACKUP_ID="${BACKUP_ID:-backup-$timestamp-$$}"
    BACKUP_DIR="/tmp/$BACKUP_ID"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create backup in: $BACKUP_DIR"
        return 0
    fi

    mkdir -p "$BACKUP_DIR"

    # Backup current container states
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" > "$BACKUP_DIR/container-states.txt" || true

    # Backup service configuration
    SERVICE_DIR="$DEPLOY_PATH/$SERVICE_NAME"
    if [[ -f "$SERVICE_DIR/docker-compose.yml" ]]; then
        cp "$SERVICE_DIR/docker-compose.yml" "$BACKUP_DIR/${SERVICE_NAME}-docker-compose.yml.bak"
    elif [[ -f "$SERVICE_DIR/docker-compose.yaml" ]]; then
        cp "$SERVICE_DIR/docker-compose.yaml" "$BACKUP_DIR/${SERVICE_NAME}-docker-compose.yml.bak"
    fi

    # Backup environment file
    if [[ -f "$SERVICE_DIR/.env" ]]; then
        cp "$SERVICE_DIR/.env" "$BACKUP_DIR/${SERVICE_NAME}.env.bak"
    fi

    # Create backup metadata
    cat > "$BACKUP_DIR/backup-metadata.json" << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "service": "$SERVICE_NAME",
    "backup_id": "$BACKUP_ID",
    "created_by": "deploy-service.sh",
    "git_commit": "$(git rev-parse HEAD 2>/dev/null || echo 'unknown')",
    "script_version": "1.0"
}
EOF

    # Set backup directory permissions
    chmod -R 755 "$BACKUP_DIR"

    log_success "Backup created: $BACKUP_ID"
    export BACKUP_ID BACKUP_DIR
}

# Execute the deployment
deploy_service() {
    log_info "Deploying service: $SERVICE_NAME"

    local service_dir="$DEPLOY_PATH/$SERVICE_NAME"
    cd "$service_dir"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute deployment commands:"
        echo "  cd $service_dir"
        echo "  docker compose pull"
        echo "  docker compose up -d --remove-orphans --wait"
        return 0
    fi

    local start_time=$(date +%s)

    # Pull latest images
    log_info "Pulling latest images..."
    if ! timeout "$DEPLOYMENT_TIMEOUT" docker compose pull; then
        log_error "Failed to pull images for $SERVICE_NAME"
        return 3
    fi

    # Deploy with zero downtime
    log_info "Executing rolling deployment..."
    if ! timeout "$DEPLOYMENT_TIMEOUT" docker compose up -d --remove-orphans --wait; then
        log_error "Deployment failed for $SERVICE_NAME"
        return 3
    fi

    local end_time=$(date +%s)
    local deploy_time=$((end_time - start_time))

    # Wait a moment for containers to stabilize
    log_info "Waiting for containers to stabilize..."
    sleep 5

    # Verify containers are running
    local running_containers
    local total_containers
    running_containers=$(docker compose ps --services --filter "status=running" | wc -l)
    total_containers=$(docker compose ps --services | wc -l)

    if [[ $running_containers -eq $total_containers ]] && [[ $total_containers -gt 0 ]]; then
        log_success "Deployment completed successfully for $SERVICE_NAME"
        log_info "Deployment time: ${deploy_time}s"
        log_info "Containers: $running_containers/$total_containers running"
    else
        log_error "Some containers failed to start for $SERVICE_NAME"
        log_error "Containers: $running_containers/$total_containers running"
        return 3
    fi

    export DEPLOYMENT_TIME=$deploy_time
}

# Perform health checks
health_check() {
    if [[ "$SKIP_HEALTH_CHECK" == "true" ]]; then
        log_info "Skipping health checks (--skip-health-check)"
        return 0
    fi

    log_info "Performing health checks for $SERVICE_NAME..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would perform health checks"
        return 0
    fi

    local service_dir="$DEPLOY_PATH/$SERVICE_NAME"
    cd "$service_dir"

    local health_start=$(date +%s)

    # Basic container health check
    local running_containers
    local total_containers
    running_containers=$(docker compose ps --services --filter "status=running" | wc -l)
    total_containers=$(docker compose ps --services | wc -l)

    if [[ $running_containers -ne $total_containers ]]; then
        log_error "Health check failed: $running_containers/$total_containers containers running"
        return 4
    fi

    # Check for unhealthy containers (with health checks defined)
    local unhealthy_containers
    unhealthy_containers=$(docker compose ps --format json 2>/dev/null | jq -r 'select(.Health == "unhealthy") | .Name' || echo "")
    if [[ -n "$unhealthy_containers" ]]; then
        log_error "Health check failed: unhealthy containers found: $unhealthy_containers"
        return 4
    fi

    # Service-specific health checks
    case "$SERVICE_NAME" in
        "vault")
            log_info "Performing Vault-specific health check..."
            if ! curl -s -f "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
                log_warn "Vault API endpoint health check failed"
                if [[ "$FORCE" != "true" ]]; then
                    return 4
                fi
            fi
            ;;
        "portainer")
            log_info "Performing Portainer-specific health check..."
            if ! curl -s -f -k "https://192.168.59.2:9000/api/status" >/dev/null 2>&1; then
                log_warn "Portainer API endpoint health check failed"
                if [[ "$FORCE" != "true" ]]; then
                    return 4
                fi
            fi
            ;;
        "github-runner")
            log_info "Performing GitHub Runner-specific health check..."
            local runner_logs
            runner_logs=$(docker compose logs --tail=10 2>/dev/null | grep -i "Listening for Jobs" || echo "")
            if [[ -z "$runner_logs" ]]; then
                log_warn "GitHub runner not listening for jobs"
                if [[ "$FORCE" != "true" ]]; then
                    return 4
                fi
            fi
            ;;
    esac

    # Basic network connectivity test
    local containers
    containers=$(docker compose ps --format json | jq -r '.Name' | head -1)
    if [[ -n "$containers" ]]; then
        log_info "Testing network connectivity..."
        if ! timeout 30 docker exec "$containers" ping -c 1 -W 10 8.8.8.8 >/dev/null 2>&1; then
            log_warn "Network connectivity test failed"
            if [[ "$FORCE" != "true" ]]; then
                return 4
            fi
        fi
    fi

    local health_end=$(date +%s)
    local health_time=$((health_end - health_start))

    log_success "Health checks passed for $SERVICE_NAME (${health_time}s)"
    export HEALTH_CHECK_TIME=$health_time
}

# Rollback to previous state
rollback() {
    if [[ "$SKIP_ROLLBACK" == "true" ]]; then
        log_warn "Rollback disabled (--skip-rollback)"
        return 0
    fi

    if [[ -z "${BACKUP_DIR:-}" ]] || [[ ! -d "$BACKUP_DIR" ]]; then
        log_error "No backup available for rollback"
        return 5
    fi

    log_warn "Initiating rollback for $SERVICE_NAME..."

    local service_dir="$DEPLOY_PATH/$SERVICE_NAME"
    local backup_file="$BACKUP_DIR/${SERVICE_NAME}-docker-compose.yml.bak"

    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup configuration file not found: $backup_file"
        return 5
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would perform rollback using backup: $BACKUP_ID"
        return 0
    fi

    cd "$service_dir"

    # Stop current containers
    log_info "Stopping current containers..."
    timeout 60 docker compose down --timeout 30 || {
        log_warn "Graceful stop failed, forcing..."
        docker compose kill || true
        docker compose rm -f || true
    }

    # Restore configuration
    log_info "Restoring configuration from backup..."
    cp "$backup_file" "$service_dir/docker-compose.yml"

    # Restart with backup configuration
    log_info "Starting service with rolled back configuration..."
    if timeout 180 docker compose up -d --wait; then
        log_success "Rollback successful for $SERVICE_NAME"

        # Quick verification
        sleep 5
        local running_containers
        local total_containers
        running_containers=$(docker compose ps --services --filter "status=running" | wc -l)
        total_containers=$(docker compose ps --services | wc -l)

        if [[ $running_containers -eq $total_containers ]] && [[ $total_containers -gt 0 ]]; then
            log_success "Rollback verification passed: $running_containers/$total_containers containers running"
        else
            log_warn "Rollback verification failed: $running_containers/$total_containers containers running"
            return 5
        fi
    else
        log_error "Rollback failed for $SERVICE_NAME"
        return 5
    fi
}

# Cleanup old backups
cleanup_backups() {
    log_info "Cleaning up old backups..."

    if [[ "$DRY_RUN" == "true" ]]; then
        local old_backups
        old_backups=$(find /tmp -name "backup-*" -type d -mtime +$BACKUP_RETENTION_DAYS 2>/dev/null | wc -l)
        log_info "[DRY RUN] Would remove $old_backups backups older than $BACKUP_RETENTION_DAYS days"
        return 0
    fi

    local removed=0
    while IFS= read -r -d '' backup_dir; do
        if [[ -f "$backup_dir/backup-metadata.json" ]]; then
            rm -rf "$backup_dir"
            ((removed++))
        fi
    done < <(find /tmp -name "backup-*" -type d -mtime +$BACKUP_RETENTION_DAYS -print0 2>/dev/null)

    if [[ $removed -gt 0 ]]; then
        log_info "Removed $removed old backups"
    fi
}

# Generate deployment report
generate_report() {
    log_info "Generating deployment report..."

    local report_file="/tmp/deploy-${SERVICE_NAME}-$(date +%Y%m%d-%H%M%S).json"

    cat > "$report_file" << EOF
{
    "service": "$SERVICE_NAME",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "deployment": {
        "status": "${DEPLOYMENT_STATUS:-unknown}",
        "time_seconds": ${DEPLOYMENT_TIME:-0},
        "backup_id": "${BACKUP_ID:-}",
        "dry_run": $DRY_RUN,
        "forced": $FORCE
    },
    "health_check": {
        "performed": $([ "$SKIP_HEALTH_CHECK" = "true" ] && echo "false" || echo "true"),
        "status": "${HEALTH_CHECK_STATUS:-unknown}",
        "time_seconds": ${HEALTH_CHECK_TIME:-0}
    },
    "rollback": {
        "enabled": $([ "$SKIP_ROLLBACK" = "true" ] && echo "false" || echo "true"),
        "performed": "${ROLLBACK_PERFORMED:-false}",
        "status": "${ROLLBACK_STATUS:-not_performed}"
    },
    "environment": {
        "hostname": "$(hostname)",
        "user": "$(whoami)",
        "script_version": "1.0",
        "git_commit": "$(git rev-parse HEAD 2>/dev/null || echo 'unknown')"
    }
}
EOF

    log_info "Report generated: $report_file"
    export DEPLOYMENT_REPORT="$report_file"
}

# Signal handlers
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment script exiting with code $exit_code"
    fi
    exit $exit_code
}

interrupt_handler() {
    log_warn "Deployment interrupted by user"
    exit 130
}

# Main execution function
main() {
    # Set signal handlers
    trap cleanup_on_exit EXIT
    trap interrupt_handler SIGINT SIGTERM

    log_info "Starting dockermaster service deployment script"
    log_info "Service: $SERVICE_NAME"
    log_info "Dry run: $DRY_RUN"

    # Execute deployment pipeline
    validate_environment
    load_secrets
    create_backup

    # Deployment execution
    if deploy_service; then
        DEPLOYMENT_STATUS="success"
        log_success "Service deployment completed successfully"

        # Health checks
        if health_check; then
            HEALTH_CHECK_STATUS="passed"
            log_success "All health checks passed"
        else
            HEALTH_CHECK_STATUS="failed"
            log_error "Health checks failed"

            if [[ "$FORCE" == "true" ]]; then
                log_warn "Continuing despite health check failures (--force)"
            else
                log_warn "Initiating automatic rollback due to health check failure"
                if rollback; then
                    ROLLBACK_PERFORMED="true"
                    ROLLBACK_STATUS="success"
                    log_success "Automatic rollback completed successfully"
                    DEPLOYMENT_STATUS="rolled_back"
                else
                    ROLLBACK_PERFORMED="true"
                    ROLLBACK_STATUS="failed"
                    log_error "Automatic rollback failed"
                    DEPLOYMENT_STATUS="failed"
                fi
            fi
        fi
    else
        DEPLOYMENT_STATUS="failed"
        log_error "Service deployment failed"

        if [[ "$SKIP_ROLLBACK" != "true" ]]; then
            log_warn "Initiating automatic rollback due to deployment failure"
            if rollback; then
                ROLLBACK_PERFORMED="true"
                ROLLBACK_STATUS="success"
                log_success "Automatic rollback completed successfully"
                DEPLOYMENT_STATUS="rolled_back"
            else
                ROLLBACK_PERFORMED="true"
                ROLLBACK_STATUS="failed"
                log_error "Automatic rollback failed"
            fi
        fi
    fi

    # Cleanup and reporting
    cleanup_backups
    generate_report

    # Final status
    case "$DEPLOYMENT_STATUS" in
        "success")
            log_success "✅ Deployment completed successfully"
            exit 0
            ;;
        "rolled_back")
            log_warn "⚠️ Deployment rolled back"
            exit 3
            ;;
        "failed")
            log_error "❌ Deployment failed"
            exit 3
            ;;
        *)
            log_error "❓ Unknown deployment status: $DEPLOYMENT_STATUS"
            exit 1
            ;;
    esac
}

# Entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_args "$@"
    main
fi
