#!/bin/bash
# Docker Compose to Portainer Stack Conversion Script
# Converts existing docker-compose.yml files to Portainer-compatible stacks

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_DIR="$PROJECT_ROOT/dockermaster/docker/compose"
TEMPLATES_DIR="$PROJECT_ROOT/dockermaster/stacks/templates"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "${BLUE}[CONVERT]${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS] <service_name>

Convert a docker-compose service to Portainer-compatible stack

OPTIONS:
    -h, --help          Show this help message
    -f, --force         Overwrite existing Portainer files
    -d, --dry-run       Show what would be created without creating files
    -v, --verbose       Verbose output
    --all               Convert all services in compose directory

EXAMPLES:
    $0 nginx-rproxy
    $0 --force calibre-server
    $0 --dry-run --all

EOF
}

# Parse command line arguments
FORCE_UPDATE=false
DRY_RUN=false
VERBOSE=false
SERVICE_NAME=""
CONVERT_ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
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
        --all)
            CONVERT_ALL=true
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

# Function to extract service information from docker-compose.yml
extract_service_info() {
    local compose_file="$1"
    local service_name="$2"

    # Check if yq is available
    if ! command -v yq &> /dev/null; then
        print_warning "yq not found, using basic parsing"
        return 1
    fi

    # Extract basic service information
    local image=$(yq eval ".services.${service_name}.image // \"\"" "$compose_file")
    local ports=$(yq eval ".services.${service_name}.ports[]? // \"\"" "$compose_file" | head -1)
    local volumes=$(yq eval ".services.${service_name}.volumes[]? // \"\"" "$compose_file")

    echo "IMAGE=$image"
    echo "PORTS=$ports"
    echo "VOLUMES=$volumes"
}

# Function to create Portainer-compatible docker-compose.yml
create_portainer_compose() {
    local service_dir="$1"
    local service_name="$2"
    local original_compose="$service_dir/docker-compose.yml"
    local portainer_compose="$service_dir/docker-compose.portainer.yml"

    if [[ ! -f "$original_compose" ]]; then
        print_warning "Original compose file not found: $original_compose"
        return 1
    fi

    if [[ -f "$portainer_compose" && "$FORCE_UPDATE" == false ]]; then
        print_warning "Portainer compose file exists: $portainer_compose (use --force to overwrite)"
        return 1
    fi

    log_verbose "Creating Portainer compose file: $portainer_compose"

    if [[ "$DRY_RUN" == false ]]; then
        # Copy original and add Portainer-specific labels
        cp "$original_compose" "$portainer_compose"

        # Add Portainer-specific modifications
        cat >> "$portainer_compose" << 'EOF'

# Portainer-specific labels added during conversion
# These labels enable GitOps functionality and monitoring
EOF

        # Use yq to add labels if available
        if command -v yq &> /dev/null; then
            yq eval -i '.services.*.labels."portainer.autodeploy" = "true"' "$portainer_compose" 2>/dev/null || true
            yq eval -i '.services.*.labels."com.centurylinklabs.watchtower.enable" = "true"' "$portainer_compose" 2>/dev/null || true
        fi
    fi

    print_status "Created: $portainer_compose"
}

# Function to create stack configuration JSON
create_stack_config() {
    local service_dir="$1"
    local service_name="$2"
    local config_file="$service_dir/portainer-stack-config.json"

    if [[ -f "$config_file" && "$FORCE_UPDATE" == false ]]; then
        print_warning "Stack config exists: $config_file (use --force to overwrite)"
        return 1
    fi

    log_verbose "Creating stack configuration: $config_file"

    if [[ "$DRY_RUN" == false ]]; then
        # Create configuration based on template
        cat > "$config_file" << EOF
{
  "name": "${service_name}",
  "composeFile": "dockermaster/docker/compose/${service_name}/docker-compose.portainer.yml",
  "repositoryUrl": "https://github.com/luiscamaral/home-lab-inventory",
  "repositoryReference": "refs/heads/main",
  "created": "$(date +%Y-%m-%d)",
  "migration_phase": "conversion",
  "note": "Stack configuration created by conversion script",

  "env": [
    {
      "name": "PUID",
      "value": "1000",
      "description": "Process User ID for file permissions"
    },
    {
      "name": "PGID",
      "value": "1000",
      "description": "Process Group ID for file permissions"
    },
    {
      "name": "TZ",
      "value": "UTC",
      "description": "Timezone setting"
    }
  ],

  "portainer": {
    "webhook": {
      "enabled": true,
      "token": "GENERATE_IN_PORTAINER",
      "url": "https://192.168.59.2:9000/api/webhooks/WEBHOOK_ID"
    },
    "autodeploy": true
  },

  "gitops": {
    "enabled": true,
    "autoUpdate": true,
    "pullPolicyMode": "Always"
  },

  "monitoring": {
    "healthcheck": {
      "enabled": true
    },
    "watchtower": {
      "enabled": true
    }
  }
}
EOF
    fi

    print_status "Created: $config_file"
}

# Function to convert a single service
convert_service() {
    local service_name="$1"
    local service_dir="$COMPOSE_DIR/$service_name"

    print_header "Converting service: $service_name"

    # Check if service directory exists
    if [[ ! -d "$service_dir" ]]; then
        print_error "Service directory not found: $service_dir"
        return 1
    fi

    # Create Portainer compose file
    if ! create_portainer_compose "$service_dir" "$service_name"; then
        print_warning "Failed to create Portainer compose file for $service_name"
    fi

    # Create stack configuration
    if ! create_stack_config "$service_dir" "$service_name"; then
        print_warning "Failed to create stack configuration for $service_name"
    fi

    print_status "Conversion completed for: $service_name"
}

# Main conversion logic
if [[ "$CONVERT_ALL" == true ]]; then
    print_header "Converting all services in $COMPOSE_DIR"

    # Find all service directories
    for service_dir in "$COMPOSE_DIR"/*/; do
        if [[ -d "$service_dir" ]]; then
            service_name=$(basename "$service_dir")

            # Skip if not a service directory (no docker-compose.yml)
            if [[ ! -f "$service_dir/docker-compose.yml" ]]; then
                log_verbose "Skipping $service_name (no docker-compose.yml)"
                continue
            fi

            convert_service "$service_name"
        fi
    done

elif [[ -n "$SERVICE_NAME" ]]; then
    convert_service "$SERVICE_NAME"

else
    print_error "Service name required or use --all"
    usage
    exit 1
fi

print_header "Conversion Summary"
print_status "Templates created in: $TEMPLATES_DIR"
print_status "Service configurations updated in compose directories"
print_status ""
print_status "Next steps:"
print_status "1. Review generated docker-compose.portainer.yml files"
print_status "2. Update environment variables in portainer-stack-config.json"
print_status "3. Deploy to Portainer using: scripts/portainer/deploy-stack.sh"
print_status "4. Configure GitHub webhooks for GitOps automation"
