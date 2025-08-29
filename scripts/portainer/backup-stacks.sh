#!/bin/bash
# Portainer Stack Backup Script
# Creates backups of Portainer stack configurations and data

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKUP_DIR="/nfs/dockermaster/backups/portainer"
PORTAINER_URL="https://192.168.59.2:9000"
PORTAINER_API="$PORTAINER_URL/api"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Backup Portainer stack configurations and data

OPTIONS:
    -h, --help              Show this help message
    -t, --token TOKEN       Portainer API token (required)
    -o, --output-dir DIR    Backup output directory (default: $BACKUP_DIR)
    -s, --stack STACK       Backup specific stack only
    --skip-data             Skip data volume backups (config only)
    --compression LEVEL     Compression level 1-9 (default: 6)
    -v, --verbose           Verbose output

EXAMPLES:
    $0 --token abc123
    $0 -t abc123 -s calibre-server
    $0 -t abc123 --skip-data -v

EOF
}

# Parse command line arguments
PORTAINER_TOKEN=""
OUTPUT_DIR="$BACKUP_DIR"
SPECIFIC_STACK=""
SKIP_DATA=false
COMPRESSION_LEVEL=6
VERBOSE=false

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
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -s|--stack)
            SPECIFIC_STACK="$2"
            shift 2
            ;;
        --skip-data)
            SKIP_DATA=true
            shift
            ;;
        --compression)
            COMPRESSION_LEVEL="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

log_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        print_status "$1"
    fi
}

# Validate required parameters
if [[ -z "$PORTAINER_TOKEN" ]]; then
    print_error "Portainer API token is required (-t/--token)"
    exit 1
fi

# Create backup directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$OUTPUT_DIR/stack-backup-$TIMESTAMP"

print_status "Creating backup directory: $BACKUP_PATH"
mkdir -p "$BACKUP_PATH"

# Function to make API requests
portainer_api() {
    local method="$1"
    local endpoint="$2"
    
    log_verbose "API Request: $method $PORTAINER_API$endpoint"
    
    curl -s -X "$method" \
        -H "Authorization: Bearer $PORTAINER_TOKEN" \
        -H "Content-Type: application/json" \
        "$PORTAINER_API$endpoint"
}

# Backup Portainer configuration
print_status "Backing up Portainer configuration..."

# Get all stacks
STACKS=$(portainer_api GET "/stacks")
echo "$STACKS" > "$BACKUP_PATH/stacks.json"

log_verbose "Found $(echo "$STACKS" | jq length) stacks"

# Get endpoints
ENDPOINTS=$(portainer_api GET "/endpoints")
echo "$ENDPOINTS" > "$BACKUP_PATH/endpoints.json"

# Process each stack
echo "$STACKS" | jq -r '.[].Name' | while read -r stack_name; do
    if [[ -n "$SPECIFIC_STACK" && "$stack_name" != "$SPECIFIC_STACK" ]]; then
        log_verbose "Skipping stack: $stack_name (not specified)"
        continue
    fi
    
    print_status "Processing stack: $stack_name"
    
    # Get stack details
    STACK_INFO=$(echo "$STACKS" | jq ".[] | select(.Name == \"$stack_name\")")
    STACK_ID=$(echo "$STACK_INFO" | jq -r '.Id')
    
    # Create stack-specific backup directory
    STACK_BACKUP_DIR="$BACKUP_PATH/stacks/$stack_name"
    mkdir -p "$STACK_BACKUP_DIR"
    
    # Save stack configuration
    echo "$STACK_INFO" > "$STACK_BACKUP_DIR/stack-config.json"
    
    # Get stack file content
    if [[ "$STACK_ID" != "null" ]]; then
        STACK_FILE=$(portainer_api GET "/stacks/$STACK_ID/file")
        echo "$STACK_FILE" > "$STACK_BACKUP_DIR/docker-compose.yml"
        
        # Get stack environment variables
        ENV_VARS=$(echo "$STACK_INFO" | jq '.Env // []')
        echo "$ENV_VARS" > "$STACK_BACKUP_DIR/environment.json"
    fi
    
    # Backup data volumes if not skipping
    if [[ "$SKIP_DATA" == false ]]; then
        print_status "Backing up data volumes for: $stack_name"
        
        # Extract volume information from stack
        VOLUMES=$(echo "$STACK_FILE" | yq eval '.services.*.volumes[]?' 2>/dev/null || echo "")
        
        if [[ -n "$VOLUMES" ]]; then
            echo "$VOLUMES" | while read -r volume; do
                if [[ "$volume" =~ ^/nfs/ ]]; then
                    HOST_PATH=$(echo "$volume" | cut -d: -f1)
                    VOLUME_NAME=$(basename "$HOST_PATH")
                    
                    if [[ -d "$HOST_PATH" ]]; then
                        log_verbose "Backing up volume: $HOST_PATH"
                        tar -czf "$STACK_BACKUP_DIR/${VOLUME_NAME}-data.tar.gz" \
                            -C "$(dirname "$HOST_PATH")" "$(basename "$HOST_PATH")" \
                            --transform "s/^$(basename "$HOST_PATH")/$VOLUME_NAME/" \
                            2>/dev/null || print_warning "Failed to backup volume: $HOST_PATH"
                    fi
                fi
            done
        fi
    fi
done

# Create backup manifest
print_status "Creating backup manifest..."
cat > "$BACKUP_PATH/backup-manifest.json" << EOF
{
  "timestamp": "$TIMESTAMP",
  "backup_type": "portainer-stacks",
  "portainer_url": "$PORTAINER_URL",
  "specific_stack": "$SPECIFIC_STACK",
  "skip_data": $SKIP_DATA,
  "compression_level": $COMPRESSION_LEVEL,
  "stack_count": $(echo "$STACKS" | jq length),
  "files": {
    "stacks_config": "stacks.json",
    "endpoints_config": "endpoints.json",
    "individual_stacks": "stacks/"
  }
}
EOF

# Create compressed archive if requested
if [[ "$COMPRESSION_LEVEL" -gt 0 ]]; then
    print_status "Creating compressed archive..."
    ARCHIVE_NAME="portainer-backup-$TIMESTAMP.tar.gz"
    
    tar -czf "$OUTPUT_DIR/$ARCHIVE_NAME" \
        -C "$OUTPUT_DIR" "$(basename "$BACKUP_PATH")" \
        --remove-files
    
    print_status "Backup archive created: $OUTPUT_DIR/$ARCHIVE_NAME"
    BACKUP_PATH="$OUTPUT_DIR/$ARCHIVE_NAME"
fi

# Generate backup report
print_status "Backup completed successfully"
print_status "Location: $BACKUP_PATH"
print_status "Size: $(du -sh "$BACKUP_PATH" | cut -f1)"

# Create restore instructions
cat > "$OUTPUT_DIR/restore-instructions-$TIMESTAMP.md" << EOF
# Portainer Stack Backup Restore Instructions

**Backup Date**: $(date)
**Backup Location**: $BACKUP_PATH

## Restore Process

### 1. Extract Backup (if compressed)
\`\`\`bash
cd $OUTPUT_DIR
tar -xzf portainer-backup-$TIMESTAMP.tar.gz
\`\`\`

### 2. Review Stack Configurations
\`\`\`bash
cat $BACKUP_PATH/backup-manifest.json
ls $BACKUP_PATH/stacks/
\`\`\`

### 3. Restore Individual Stack
\`\`\`bash
# Use the deploy-stack.sh script with backup data
./scripts/portainer/deploy-stack.sh --token <token> <stack-name>
\`\`\`

### 4. Restore Data Volumes
For each stack with data backups:
\`\`\`bash
cd $BACKUP_PATH/stacks/<stack-name>/
tar -xzf <volume>-data.tar.gz -C /nfs/dockermaster/
\`\`\`

## Validation
After restore, verify:
- [ ] Stack appears in Portainer UI
- [ ] All containers are running
- [ ] Service endpoints are accessible
- [ ] Data integrity confirmed

EOF

print_status "Restore instructions: $OUTPUT_DIR/restore-instructions-$TIMESTAMP.md"