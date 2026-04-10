#!/bin/bash
# Extract Docker Compose Configurations Script
# Part of dockermaster-recovery documentation framework
# Created: 2025-08-28

set -euo pipefail

# Configuration
DOCKERMASTER_HOST="dockermaster"
DOCKER_BASE_PATH="/nfs/dockermaster/docker"
OUTPUT_DIR="$(dirname "$0")/../output/compose-configs"
SSH_HELPER="$(dirname "$0")/ssh-dockermaster.sh"
SCRIPT_NAME=$(basename "$0")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1" >&2
    fi
}

# Usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] [SERVICE_NAME...]

Extract Docker Compose configurations from dockermaster for documentation.

Options:
    -a, --all           Extract all services (default if no services specified)
    -o, --output DIR    Output directory (default: $OUTPUT_DIR)
    -f, --format FORMAT Output format: raw, yaml, json (default: raw)
    -l, --list          List available services and exit
    -c, --check         Check which services have compose files
    -v, --verbose       Enable verbose output
    -d, --debug         Enable debug output
    -h, --help          Show this help message

Arguments:
    SERVICE_NAME        One or more service names to extract

Examples:
    $SCRIPT_NAME --all                    # Extract all services
    $SCRIPT_NAME nginx grafana            # Extract specific services
    $SCRIPT_NAME --list                   # List all available services
    $SCRIPT_NAME --check                  # Check compose file availability
    $SCRIPT_NAME --format json nginx      # Extract nginx config as JSON

Output Structure:
    output/compose-configs/
    ├── nginx/
    │   ├── docker-compose.yml
    │   ├── metadata.json
    │   └── analysis.txt
    ├── grafana/
    │   └── ...
    └── summary.json

Environment Variables:
    DEBUG=1             Enable debug output
    SSH_TIMEOUT=30      SSH connection timeout (seconds)
EOF
}

# Initialize output directory
init_output_dir() {
    local output_dir="$1"

    log_info "Initializing output directory: $output_dir"

    mkdir -p "$output_dir"

    # Create summary file
    cat > "$output_dir/summary.json" << 'EOF'
{
    "extraction_date": "",
    "dockermaster_host": "",
    "total_services": 0,
    "successful_extractions": 0,
    "failed_extractions": 0,
    "services": {}
}
EOF

    log_success "Output directory initialized"
}

# Check if SSH helper is available and working
check_ssh_connection() {
    log_info "Checking SSH connection to dockermaster..."

    if [[ ! -x "$SSH_HELPER" ]]; then
        log_error "SSH helper script not found or not executable: $SSH_HELPER"
        log_info "Please run the SSH setup first"
        return 1
    fi

    # Check if connection is active, establish if needed
    if ! "$SSH_HELPER" status >/dev/null 2>&1; then
        log_info "Establishing SSH connection..."
        if ! "$SSH_HELPER" connect; then
            log_error "Failed to establish SSH connection"
            return 1
        fi
    fi

    log_success "SSH connection ready"
    return 0
}

# List available services on dockermaster
list_services() {
    log_info "Listing available services on dockermaster..."

    local services
    services=$("$SSH_HELPER" exec "find $DOCKER_BASE_PATH -maxdepth 1 -type d -name '[!.]*' | sort" 2>/dev/null) || {
        log_error "Failed to list services"
        return 1
    }

    if [[ -z "$services" ]]; then
        log_warning "No services found in $DOCKER_BASE_PATH"
        return 1
    fi

    echo "Available services:"
    echo "$services" | sed "s|$DOCKER_BASE_PATH/||g" | while read -r service; do
        echo "  - $service"
    done

    local count
    count=$(echo "$services" | wc -l)
    log_success "Found $count services"

    return 0
}

# Check which services have compose files
check_compose_availability() {
    log_info "Checking compose file availability..."

    local services
    services=$("$SSH_HELPER" exec "find $DOCKER_BASE_PATH -maxdepth 1 -type d -name '[!.]*' | sort" 2>/dev/null) || {
        log_error "Failed to list services"
        return 1
    }

    echo "Service compose file status:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local total=0 available=0

    echo "$services" | sed "s|$DOCKER_BASE_PATH/||g" | while read -r service; do
        total=$((total + 1))

        local compose_file="$DOCKER_BASE_PATH/$service/docker-compose.yml"
        if "$SSH_HELPER" exec "test -f '$compose_file'" 2>/dev/null; then
            echo -e "  ✅ $service ${GREEN}(compose file exists)${NC}"
            available=$((available + 1))
        else
            echo -e "  ❌ $service ${RED}(no compose file)${NC}"
        fi
    done

    log_success "Compose availability check completed"
    return 0
}

# Extract metadata about a service
extract_service_metadata() {
    local service="$1"
    local output_dir="$2"

    log_debug "Extracting metadata for service: $service"

    local service_path="$DOCKER_BASE_PATH/$service"
    local metadata_file="$output_dir/$service/metadata.json"

    # Create metadata JSON
    cat > "$metadata_file" << EOF
{
    "service_name": "$service",
    "extraction_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "dockermaster_path": "$service_path",
    "files": {
        "compose_file": null,
        "env_file": null,
        "additional_files": []
    },
    "directory_contents": [],
    "file_sizes": {},
    "permissions": {},
    "last_modified": {}
}
EOF

    # Get directory contents
    local dir_contents
    dir_contents=$("$SSH_HELPER" exec "ls -la '$service_path'" 2>/dev/null || echo "") || true

    if [[ -n "$dir_contents" ]]; then
        # Create a temporary file for directory contents
        local temp_contents
        temp_contents=$(mktemp)
        echo "$dir_contents" > "$temp_contents"

        # Update metadata with directory contents (simplified JSON-safe format)
        local contents_json
        contents_json=$(echo "$dir_contents" | tail -n +2 | awk '{print "\"" $NF "\""}' | tr '\n' ',' | sed 's/,$//')

        # Update JSON using a simple approach
        sed -i.bak "s/\"directory_contents\": \[\]/\"directory_contents\": [$contents_json]/" "$metadata_file"
        rm -f "$metadata_file.bak"
        rm -f "$temp_contents"
    fi

    log_debug "Metadata extracted for $service"
}

# Extract compose file and related configs
extract_service_config() {
    local service="$1"
    local output_dir="$2"
    local format="${3:-raw}"

    log_info "Extracting configuration for service: $service"

    local service_path="$DOCKER_BASE_PATH/$service"
    local service_output_dir="$output_dir/$service"

    # Create service output directory
    mkdir -p "$service_output_dir"

    # Check if service directory exists
    if ! "$SSH_HELPER" exec "test -d '$service_path'" 2>/dev/null; then
        log_error "Service directory not found: $service_path"
        return 1
    fi

    # Extract docker-compose.yml
    local compose_file="$service_path/docker-compose.yml"
    if "$SSH_HELPER" exec "test -f '$compose_file'" 2>/dev/null; then
        log_debug "Extracting docker-compose.yml for $service"

        "$SSH_HELPER" exec "cat '$compose_file'" > "$service_output_dir/docker-compose.yml" || {
            log_error "Failed to extract compose file for $service"
            return 1
        }

        # Convert to different formats if requested
        case "$format" in
            "json")
                if command -v yq >/dev/null 2>&1; then
                    yq eval -o=json "$service_output_dir/docker-compose.yml" > "$service_output_dir/docker-compose.json"
                    log_debug "Created JSON version for $service"
                else
                    log_warning "yq not found, skipping JSON conversion for $service"
                fi
                ;;
            "yaml")
                # Already in YAML format, just copy
                cp "$service_output_dir/docker-compose.yml" "$service_output_dir/docker-compose.yaml"
                ;;
        esac

        log_success "Compose file extracted for $service"
    else
        log_warning "No compose file found for $service"
        echo "# No docker-compose.yml found" > "$service_output_dir/no-compose.txt"
    fi

    # Extract .env file if it exists
    local env_file="$service_path/.env"
    if "$SSH_HELPER" exec "test -f '$env_file'" 2>/dev/null; then
        log_debug "Extracting .env file for $service"
        "$SSH_HELPER" exec "cat '$env_file'" > "$service_output_dir/.env" || true
    fi

    # Extract other common configuration files
    local config_files=(".env.local" ".env.production" "config.yml" "config.json" "settings.conf")
    for config_file in "${config_files[@]}"; do
        local full_path="$service_path/$config_file"
        if "$SSH_HELPER" exec "test -f '$full_path'" 2>/dev/null; then
            log_debug "Extracting $config_file for $service"
            "$SSH_HELPER" exec "cat '$full_path'" > "$service_output_dir/$config_file" 2>/dev/null || true
        fi
    done

    # Create service analysis
    create_service_analysis "$service" "$service_output_dir"

    # Extract metadata
    extract_service_metadata "$service" "$output_dir"

    log_success "Service configuration extracted: $service"
    return 0
}

# Create analysis of the service configuration
create_service_analysis() {
    local service="$1"
    local service_output_dir="$2"

    log_debug "Creating analysis for service: $service"

    local analysis_file="$service_output_dir/analysis.txt"

    cat > "$analysis_file" << EOF
Service Analysis: $service
Generated: $(date)

============================================

EOF

    # Analyze compose file if it exists
    if [[ -f "$service_output_dir/docker-compose.yml" ]]; then
        cat >> "$analysis_file" << EOF
DOCKER COMPOSE ANALYSIS:

Services defined:
$(grep -E "^  [a-zA-Z]" "$service_output_dir/docker-compose.yml" | sed 's/:.*$//' | sed 's/^/  - /' || echo "  - Could not parse services")

Images used:
$(grep -E "image:" "$service_output_dir/docker-compose.yml" | sed 's/.*image: */  - /' || echo "  - No images found")

Ports exposed:
$(grep -E "ports:" -A 10 "$service_output_dir/docker-compose.yml" | grep -E "^\s*-" | sed 's/^/  /' || echo "  - No ports found")

Volumes:
$(grep -E "volumes:" -A 10 "$service_output_dir/docker-compose.yml" | grep -E "^\s*-" | sed 's/^/  /' || echo "  - No volumes found")

Networks:
$(grep -E "networks:" -A 5 "$service_output_dir/docker-compose.yml" | grep -E "^\s*-" | sed 's/^/  /' || echo "  - Default network")

EOF
    else
        cat >> "$analysis_file" << EOF
DOCKER COMPOSE ANALYSIS:
  - No docker-compose.yml file found

EOF
    fi

    # Analyze environment file if it exists
    if [[ -f "$service_output_dir/.env" ]]; then
        cat >> "$analysis_file" << EOF
ENVIRONMENT VARIABLES:
$(grep -v "^#" "$service_output_dir/.env" 2>/dev/null | grep -v "^$" | sed 's/=.*//' | sed 's/^/  - /' || echo "  - No variables found")

EOF
    fi

    log_debug "Analysis created for $service"
}

# Update summary JSON with results
update_summary() {
    local output_dir="$1"
    local service="$2"
    local success="${3:-true}"

    local summary_file="$output_dir/summary.json"

    # Simple JSON update (not robust, but works for our case)
    if [[ "$success" == "true" ]]; then
        # This is a simplified approach - in production, use jq or proper JSON parsing
        log_debug "Marking $service as successfully extracted"
    else
        log_debug "Marking $service as failed extraction"
    fi

    # Update extraction date
    local current_date
    current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    sed -i.bak "s/\"extraction_date\": \"\"/\"extraction_date\": \"$current_date\"/" "$summary_file"
    sed -i.bak "s/\"dockermaster_host\": \"\"/\"dockermaster_host\": \"$DOCKERMASTER_HOST\"/" "$summary_file"

    rm -f "$summary_file.bak"
}

# Main extraction function
extract_services() {
    local services=("$@")
    local output_dir="${OUTPUT_DIR}"
    local format="${FORMAT:-raw}"

    if [[ ${#services[@]} -eq 0 ]]; then
        log_info "No services specified, extracting all services"

        # Get all services
        local all_services
        all_services=$("$SSH_HELPER" exec "find $DOCKER_BASE_PATH -maxdepth 1 -type d -name '[!.]*' | sort" 2>/dev/null) || {
            log_error "Failed to list services"
            return 1
        }

        # Convert to array of service names
        while IFS= read -r service_path; do
            services+=($(basename "$service_path"))
        done <<< "$all_services"
    fi

    log_info "Extracting configurations for ${#services[@]} services"

    # Initialize output directory
    init_output_dir "$output_dir"

    local successful=0
    local failed=0

    # Extract each service
    for service in "${services[@]}"; do
        log_info "Processing service: $service ($(($successful + $failed + 1))/${#services[@]})"

        if extract_service_config "$service" "$output_dir" "$format"; then
            update_summary "$output_dir" "$service" "true"
            successful=$((successful + 1))
            log_success "✅ $service"
        else
            update_summary "$output_dir" "$service" "false"
            failed=$((failed + 1))
            log_error "❌ $service"
        fi
    done

    # Final summary
    log_info "Extraction completed"
    log_success "Successfully extracted: $successful services"

    if [[ $failed -gt 0 ]]; then
        log_warning "Failed extractions: $failed services"
    fi

    log_info "Output saved to: $output_dir"

    return 0
}

# Main function
main() {
    local services=()
    local list_only=false
    local check_only=false
    local format="raw"
    local verbose=false
    local debug=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--all)
                services=()  # Will be filled by extract_services
                shift
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -f|--format)
                format="$2"
                shift 2
                ;;
            -l|--list)
                list_only=true
                shift
                ;;
            -c|--check)
                check_only=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -d|--debug)
                debug=true
                export DEBUG=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                services+=("$1")
                shift
                ;;
        esac
    done

    # Set global format
    FORMAT="$format"

    # Check SSH connection first
    if ! check_ssh_connection; then
        exit 1
    fi

    # Handle list and check options
    if [[ "$list_only" == "true" ]]; then
        list_services
        exit $?
    fi

    if [[ "$check_only" == "true" ]]; then
        check_compose_availability
        exit $?
    fi

    # Validate format
    case "$format" in
        raw|yaml|json)
            ;;
        *)
            log_error "Invalid format: $format. Supported: raw, yaml, json"
            exit 1
            ;;
    esac

    # Extract services
    extract_services "${services[@]}"
}

# Run main function with all arguments
main "$@"
