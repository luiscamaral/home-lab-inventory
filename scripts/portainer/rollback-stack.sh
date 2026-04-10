#!/bin/bash
# Portainer Stack Rollback Script
# Provides emergency rollback capabilities for failed deployments

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PORTAINER_URL="https://192.168.59.2:9000"
PORTAINER_API="$PORTAINER_URL/api"
BACKUP_DIR="/nfs/dockermaster/backups/portainer"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[ROLLBACK]${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS] <service_name>

Rollback a Portainer stack to a previous state

OPTIONS:
    -h, --help                  Show this help message
    -t, --token TOKEN           Portainer API token (required)
    -b, --backup-timestamp TS   Specific backup timestamp to restore
    -l, --list-backups          List available backups for the service
    -m, --method METHOD         Rollback method: git|backup|config (default: git)
    -c, --commit HASH           Git commit hash to rollback to (git method)
    -f, --force                 Force rollback without confirmation
    -v, --verbose               Verbose output
    --data-only                 Restore data volumes only (skip configuration)
    --config-only               Restore configuration only (skip data)

ROLLBACK METHODS:
    git       - Revert git repository to previous commit (recommended)
    backup    - Restore from Portainer stack backup
    config    - Restore using previous stack configuration

EXAMPLES:
    $0 --token abc123 calibre-server
    $0 -t abc123 -m backup -b 20250829_140000 nginx-rproxy
    $0 -t abc123 -m git -c a1b2c3d4 vault
    $0 -l calibre-server

EOF
}

# Parse command line arguments
PORTAINER_TOKEN=""
SERVICE_NAME=""
BACKUP_TIMESTAMP=""
ROLLBACK_METHOD="git"
GIT_COMMIT=""
FORCE_ROLLBACK=false
VERBOSE=false
LIST_BACKUPS=false
DATA_ONLY=false
CONFIG_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -t|--token)
            PORTAINER_TOKEN="$2"
            shift 2
            ;;
        -b|--backup-timestamp)
            BACKUP_TIMESTAMP="$2"
            shift 2
            ;;
        -l|--list-backups)
            LIST_BACKUPS=true
            shift
            ;;
        -m|--method)
            ROLLBACK_METHOD="$2"
            shift 2
            ;;
        -c|--commit)
            GIT_COMMIT="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_ROLLBACK=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --data-only)
            DATA_ONLY=true
            shift
            ;;
        --config-only)
            CONFIG_ONLY=true
            shift
            ;;
        -*)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            if [[ -z "$SERVICE_NAME" ]]; then
                SERVICE_NAME="$1"
                shift
            else
                print_error "Multiple service names provided"
                usage
                exit 1
            fi
            ;;
    esac
done

log_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        print_status "$1"
    fi
}

# Validate required parameters
if [[ -z "$SERVICE_NAME" ]]; then
    print_error "Service name is required"
    usage
    exit 1
fi

if [[ "$LIST_BACKUPS" == false && -z "$PORTAINER_TOKEN" ]]; then
    print_error "Portainer API token is required (-t/--token)"
    exit 1
fi

# List available backups
list_backups() {
    local service="$1"

    print_header "Available backups for: $service"

    if [[ ! -d "$BACKUP_DIR" ]]; then
        print_warning "Backup directory not found: $BACKUP_DIR"
        return 1
    fi

    local found_backups=false

    for backup_path in "$BACKUP_DIR"/stack-backup-*/stacks/"$service"; do
        if [[ -d "$backup_path" ]]; then
            local backup_name=$(basename "$(dirname "$(dirname "$backup_path")")")
            local timestamp=$(echo "$backup_name" | sed 's/stack-backup-//')
            local date_readable=$(date -d "${timestamp:0:8} ${timestamp:9:2}:${timestamp:11:2}:${timestamp:13:2}" 2>/dev/null || echo "Invalid date")

            echo "  📦 $timestamp ($date_readable)"

            if [[ -f "$backup_path/stack-config.json" ]]; then
                echo "     ✅ Configuration available"
            fi

            if ls "$backup_path"/*-data.tar.gz 1> /dev/null 2>&1; then
                echo "     💾 Data backups available"
            fi

            echo ""
            found_backups=true
        fi
    done

    if [[ "$found_backups" == false ]]; then
        print_warning "No backups found for service: $service"
    fi
}

if [[ "$LIST_BACKUPS" == true ]]; then
    list_backups "$SERVICE_NAME"
    exit 0
fi

# Function to make API requests
portainer_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    local curl_args=(-s -X "$method" -H "Authorization: Bearer $PORTAINER_TOKEN" -H "Content-Type: application/json")

    if [[ -n "$data" ]]; then
        curl_args+=(-d "$data")
    fi

    log_verbose "API Request: $method $PORTAINER_API$endpoint"
    curl "${curl_args[@]}" "$PORTAINER_API$endpoint"
}

# Get stack information
print_status "Looking up stack information for: $SERVICE_NAME"
STACKS=$(portainer_api GET "/stacks")
STACK_INFO=$(echo "$STACKS" | jq ".[] | select(.Name == \"$SERVICE_NAME\")")

if [[ -z "$STACK_INFO" || "$STACK_INFO" == "null" ]]; then
    print_error "Stack not found: $SERVICE_NAME"
    exit 1
fi

STACK_ID=$(echo "$STACK_INFO" | jq -r '.Id')
print_status "Found stack ID: $STACK_ID"

# Confirmation prompt unless forced
if [[ "$FORCE_ROLLBACK" == false ]]; then
    print_warning "This will rollback the stack: $SERVICE_NAME"
    print_warning "Method: $ROLLBACK_METHOD"

    if [[ "$ROLLBACK_METHOD" == "backup" && -n "$BACKUP_TIMESTAMP" ]]; then
        print_warning "Backup timestamp: $BACKUP_TIMESTAMP"
    elif [[ "$ROLLBACK_METHOD" == "git" && -n "$GIT_COMMIT" ]]; then
        print_warning "Git commit: $GIT_COMMIT"
    fi

    read -p "Are you sure you want to proceed? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Rollback cancelled by user"
        exit 0
    fi
fi

# Execute rollback based on method
case "$ROLLBACK_METHOD" in
    "git")
        print_header "Performing Git-based rollback"

        cd "$PROJECT_ROOT"

        if [[ -n "$GIT_COMMIT" ]]; then
            print_status "Rolling back to specific commit: $GIT_COMMIT"
            git reset --hard "$GIT_COMMIT"
            git push --force origin main
        else
            # Find last good commit (simple heuristic: previous commit)
            CURRENT_COMMIT=$(git rev-parse HEAD)
            PREVIOUS_COMMIT=$(git rev-parse HEAD~1)

            print_status "Current commit: $CURRENT_COMMIT"
            print_status "Rolling back to: $PREVIOUS_COMMIT"

            git reset --hard "$PREVIOUS_COMMIT"
            git push --force origin main
        fi

        print_status "Git rollback completed - GitOps will trigger automatic deployment"
        ;;

    "backup")
        print_header "Performing backup-based rollback"

        if [[ -z "$BACKUP_TIMESTAMP" ]]; then
            # Find most recent backup
            BACKUP_TIMESTAMP=$(ls -1 "$BACKUP_DIR"/stack-backup-*/stacks/"$SERVICE_NAME" 2>/dev/null | head -1 | sed 's/.*stack-backup-\([0-9_]*\).*/\1/' || echo "")

            if [[ -z "$BACKUP_TIMESTAMP" ]]; then
                print_error "No backups found and no timestamp specified"
                exit 1
            fi

            print_status "Using most recent backup: $BACKUP_TIMESTAMP"
        fi

        BACKUP_PATH="$BACKUP_DIR/stack-backup-$BACKUP_TIMESTAMP/stacks/$SERVICE_NAME"

        if [[ ! -d "$BACKUP_PATH" ]]; then
            print_error "Backup not found: $BACKUP_PATH"
            exit 1
        fi

        # Stop current stack
        print_status "Stopping current stack..."
        portainer_api POST "/stacks/$STACK_ID/stop"

        # Restore data volumes if requested
        if [[ "$CONFIG_ONLY" == false ]]; then
            print_status "Restoring data volumes..."

            for data_file in "$BACKUP_PATH"/*-data.tar.gz; do
                if [[ -f "$data_file" ]]; then
                    print_status "Restoring: $(basename "$data_file")"
                    tar -xzf "$data_file" -C /nfs/dockermaster/ || print_warning "Failed to restore: $data_file"
                fi
            done
        fi

        # Restore configuration if requested
        if [[ "$DATA_ONLY" == false ]]; then
            print_status "Restoring stack configuration..."

            if [[ -f "$BACKUP_PATH/docker-compose.yml" ]]; then
                # Create temporary configuration for restoration
                TEMP_COMPOSE="/tmp/${SERVICE_NAME}-restore-compose.yml"
                cp "$BACKUP_PATH/docker-compose.yml" "$TEMP_COMPOSE"

                # Update stack with backup configuration
                COMPOSE_CONTENT=$(cat "$TEMP_COMPOSE" | base64 -w 0)

                UPDATE_PAYLOAD=$(cat <<EOF
{
  "stackFileContent": "$COMPOSE_CONTENT",
  "env": $(cat "$BACKUP_PATH/environment.json" 2>/dev/null || echo "[]"),
  "prune": true
}
EOF
)

                portainer_api PUT "/stacks/$STACK_ID" "$UPDATE_PAYLOAD"
                rm "$TEMP_COMPOSE"
            fi
        fi

        # Start stack
        print_status "Starting restored stack..."
        portainer_api POST "/stacks/$STACK_ID/start"
        ;;

    "config")
        print_header "Performing configuration rollback"

        SERVICE_DIR="$PROJECT_ROOT/dockermaster/docker/compose/$SERVICE_NAME"

        if [[ ! -f "$SERVICE_DIR/docker-compose.yml" ]]; then
            print_error "Original configuration not found: $SERVICE_DIR/docker-compose.yml"
            exit 1
        fi

        # Reset to original compose configuration
        print_status "Resetting to original docker-compose.yml"

        COMPOSE_CONTENT=$(cat "$SERVICE_DIR/docker-compose.yml" | base64 -w 0)

        UPDATE_PAYLOAD=$(cat <<EOF
{
  "stackFileContent": "$COMPOSE_CONTENT",
  "prune": true
}
EOF
)

        portainer_api PUT "/stacks/$STACK_ID" "$UPDATE_PAYLOAD"
        ;;

    *)
        print_error "Unknown rollback method: $ROLLBACK_METHOD"
        exit 1
        ;;
esac

# Verify rollback success
print_status "Verifying rollback..."
sleep 5

UPDATED_STACK=$(portainer_api GET "/stacks/$STACK_ID")
STACK_STATUS=$(echo "$UPDATED_STACK" | jq -r '.Status // "unknown"')

case "$STACK_STATUS" in
    1|"active")
        print_status "✅ Stack is running successfully"
        ;;
    2|"inactive")
        print_warning "⚠️  Stack is inactive - may need manual intervention"
        ;;
    *)
        print_error "❌ Stack status unknown: $STACK_STATUS"
        ;;
esac

# Generate rollback report
ROLLBACK_REPORT="/tmp/rollback-report-$(date +%Y%m%d_%H%M%S).md"

cat > "$ROLLBACK_REPORT" << EOF
# Portainer Stack Rollback Report

**Service**: $SERVICE_NAME
**Stack ID**: $STACK_ID
**Rollback Method**: $ROLLBACK_METHOD
**Timestamp**: $(date)
**Status**: $STACK_STATUS

## Rollback Details
$(case "$ROLLBACK_METHOD" in
    "git")
        echo "- Git repository reset to: ${GIT_COMMIT:-previous commit}"
        echo "- GitOps triggered automatic redeployment"
        ;;
    "backup")
        echo "- Backup timestamp: $BACKUP_TIMESTAMP"
        echo "- Configuration restored: $([[ "$DATA_ONLY" == false ]] && echo "Yes" || echo "No")"
        echo "- Data volumes restored: $([[ "$CONFIG_ONLY" == false ]] && echo "Yes" || echo "No")"
        ;;
    "config")
        echo "- Reset to original docker-compose.yml"
        ;;
esac)

## Next Steps
1. Verify service functionality
2. Check service endpoints: curl http://service-ip:port/health
3. Review container logs if issues persist
4. Consider creating new backup after successful rollback

## Service Endpoints
- Check service status in Portainer: $PORTAINER_URL
- Monitor container logs for any issues
- Validate service-specific functionality

EOF

print_status "Rollback completed for: $SERVICE_NAME"
print_status "Report generated: $ROLLBACK_REPORT"
print_status ""
print_status "Next steps:"
print_status "1. Verify service is accessible and functioning"
print_status "2. Check container logs for any errors"
print_status "3. Create new backup if rollback successful"
print_status "4. Review and address root cause of original failure"
