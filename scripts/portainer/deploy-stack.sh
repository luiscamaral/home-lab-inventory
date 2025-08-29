#!/bin/bash
# Portainer Stack Deployment Script
# Deploys a service stack to Portainer with GitOps configuration

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PORTAINER_URL="https://192.168.59.2:9000"
PORTAINER_API="$PORTAINER_URL/api"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS] <service_name>

Deploy a service to Portainer as a GitOps-enabled stack

OPTIONS:
    -h, --help              Show this help message
    -t, --token TOKEN       Portainer API token (required)
    -e, --endpoint-id ID    Portainer endpoint ID (default: 1)
    -f, --force             Force update if stack exists
    -d, --dry-run           Show what would be deployed without deploying
    -v, --verbose           Verbose output

EXAMPLES:
    $0 --token abc123 calibre-server
    $0 -t abc123 -f nginx-rproxy
    $0 -t abc123 -d vault

NOTES:
    - Service must have docker-compose.portainer.yml in dockermaster/docker/compose/<service>/
    - Service must have portainer-stack-config.json configuration
    - API token can be obtained from Portainer UI: User account -> Access tokens

EOF
}

# Parse command line arguments
PORTAINER_TOKEN=""
ENDPOINT_ID="1"
FORCE_UPDATE=false
DRY_RUN=false
VERBOSE=false
SERVICE_NAME=""

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
        -e|--endpoint-id)
            ENDPOINT_ID="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_UPDATE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
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

# Validate required parameters
if [[ -z "$SERVICE_NAME" ]]; then
    print_error "Service name is required"
    usage
    exit 1
fi

if [[ -z "$PORTAINER_TOKEN" ]]; then
    print_error "Portainer API token is required (-t/--token)"
    usage
    exit 1
fi

# Verbose logging function
log_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        print_status "$1"
    fi
}

# Check if service configuration exists
SERVICE_DIR="$PROJECT_ROOT/dockermaster/docker/compose/$SERVICE_NAME"
COMPOSE_FILE="$SERVICE_DIR/docker-compose.portainer.yml"
CONFIG_FILE="$SERVICE_DIR/portainer-stack-config.json"

if [[ ! -d "$SERVICE_DIR" ]]; then
    print_error "Service directory not found: $SERVICE_DIR"
    exit 1
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
    print_error "Portainer compose file not found: $COMPOSE_FILE"
    exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    print_error "Stack configuration not found: $CONFIG_FILE"
    exit 1
fi

print_status "Deploying service: $SERVICE_NAME"
log_verbose "Service directory: $SERVICE_DIR"
log_verbose "Compose file: $COMPOSE_FILE"
log_verbose "Config file: $CONFIG_FILE"

# Read stack configuration
STACK_CONFIG=$(cat "$CONFIG_FILE")
STACK_NAME=$(echo "$STACK_CONFIG" | jq -r '.name')
REPO_URL=$(echo "$STACK_CONFIG" | jq -r '.repositoryUrl')
REPO_REF=$(echo "$STACK_CONFIG" | jq -r '.repositoryReference')
COMPOSE_PATH=$(echo "$STACK_CONFIG" | jq -r '.composeFile')

print_status "Stack configuration loaded:"
print_status "  Stack name: $STACK_NAME"
print_status "  Repository: $REPO_URL"
print_status "  Branch: $REPO_REF"
print_status "  Compose path: $COMPOSE_PATH"

if [[ "$DRY_RUN" == true ]]; then
    print_warning "DRY RUN MODE - No actual deployment will occur"
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
    
    if [[ "$DRY_RUN" == true ]]; then
        echo '{"dry_run": true}'
        return
    fi
    
    curl "${curl_args[@]}" "$PORTAINER_API$endpoint"
}

# Check if stack already exists
print_status "Checking if stack already exists..."
EXISTING_STACKS=$(portainer_api GET "/stacks")
EXISTING_STACK_ID=$(echo "$EXISTING_STACKS" | jq -r ".[] | select(.Name == \"$STACK_NAME\") | .Id")

if [[ -n "$EXISTING_STACK_ID" && "$EXISTING_STACK_ID" != "null" ]]; then
    if [[ "$FORCE_UPDATE" == true ]]; then
        print_warning "Stack exists (ID: $EXISTING_STACK_ID) - will update due to --force"
        STACK_EXISTS=true
    else
        print_error "Stack '$STACK_NAME' already exists (ID: $EXISTING_STACK_ID)"
        print_error "Use --force to update existing stack"
        exit 1
    fi
else
    print_status "Stack does not exist - will create new stack"
    STACK_EXISTS=false
fi

# Prepare stack environment variables
print_status "Preparing environment variables..."
ENV_VARS=$(echo "$STACK_CONFIG" | jq -r '.env[]')
ENV_ARRAY="["

# Read environment variables from config
while IFS= read -r env_item; do
    if [[ -n "$env_item" ]]; then
        ENV_ARRAY+="$env_item,"
    fi
done <<< "$ENV_VARS"

# Remove trailing comma and close array
ENV_ARRAY="${ENV_ARRAY%,}]"

# Prepare stack payload
if [[ "$STACK_EXISTS" == true ]]; then
    # Update existing stack
    PAYLOAD=$(cat <<EOF
{
  "env": $ENV_ARRAY,
  "prune": true,
  "pullImage": true
}
EOF
)
    
    print_status "Updating existing stack..."
    if [[ "$DRY_RUN" == false ]]; then
        RESPONSE=$(portainer_api PUT "/stacks/$EXISTING_STACK_ID/git/redeploy?endpointId=$ENDPOINT_ID" "$PAYLOAD")
        print_status "Stack update response: $RESPONSE"
    fi
    
else
    # Create new stack
    PAYLOAD=$(cat <<EOF
{
  "name": "$STACK_NAME",
  "repositoryURL": "$REPO_URL",
  "repositoryReferenceName": "${REPO_REF#refs/heads/}",
  "composeFile": "$COMPOSE_PATH",
  "env": $ENV_ARRAY,
  "fromAppTemplate": false,
  "autoUpdate": {
    "webhook": "$(uuidgen | tr '[:upper:]' '[:lower:]')"
  }
}
EOF
)
    
    print_status "Creating new stack..."
    if [[ "$DRY_RUN" == false ]]; then
        RESPONSE=$(portainer_api POST "/stacks/repository/file/start?endpointId=$ENDPOINT_ID" "$PAYLOAD")
        print_status "Stack creation response: $RESPONSE"
        
        # Extract stack ID from response
        NEW_STACK_ID=$(echo "$RESPONSE" | jq -r '.Id // empty')
        if [[ -n "$NEW_STACK_ID" ]]; then
            print_status "Stack created with ID: $NEW_STACK_ID"
        fi
    fi
fi

# Configure webhook if stack was created successfully
if [[ "$DRY_RUN" == false && ("$STACK_EXISTS" == false || -n "${NEW_STACK_ID:-}") ]]; then
    print_status "Stack deployment completed successfully"
    
    # Get webhook URL
    STACK_ID="${NEW_STACK_ID:-$EXISTING_STACK_ID}"
    WEBHOOK_URL="$PORTAINER_URL/api/stacks/$STACK_ID/git/deploy"
    
    print_status "GitOps Configuration:"
    print_status "  Webhook URL: $WEBHOOK_URL"
    print_status "  Repository monitoring: $REPO_URL"
    print_status "  Branch: ${REPO_REF#refs/heads/}"
    print_status ""
    print_status "Next steps:"
    print_status "1. Configure GitHub webhook pointing to: $WEBHOOK_URL"
    print_status "2. Test deployment by pushing to repository"
    print_status "3. Monitor stack in Portainer UI: $PORTAINER_URL"
    
else
    if [[ "$DRY_RUN" == true ]]; then
        print_status "DRY RUN completed successfully"
    else
        print_error "Stack deployment may have failed - check Portainer logs"
    fi
fi