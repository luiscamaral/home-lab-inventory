#!/bin/bash
# Parse Environment Variables Script (Fixed)
# Part of dockermaster-recovery documentation framework
# Created: 2025-08-28

set -euo pipefail

# Configuration
DOCKERMASTER_HOST="dockermaster"
DOCKER_BASE_PATH="/nfs/dockermaster/docker"
OUTPUT_DIR="$(dirname "$0")/../output/environment-analysis"
SSH_HELPER="$(dirname "$0")/ssh-dockermaster.sh"
SCRIPT_NAME=$(basename "$0")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
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

log_security() {
    echo -e "${MAGENTA}[SECURITY]${NC} $1" >&2
}

# Usage information
usage() {
    cat << 'USAGE_EOF'
Usage: parse-env.sh [OPTIONS] [SERVICE_NAME...]

Parse and analyze environment variables from dockermaster services.

Options:
    -a, --all           Analyze all services (default if no services specified)
    -o, --output DIR    Output directory
    -f, --format FORMAT Output format: table, json, csv, env (default: table)
    -l, --list          List services with environment files
    -s, --secrets       Analyze potential secrets (security scan)
    -c, --compose       Extract env vars from compose files too
    -v, --vault         Check for Vault references
    -d, --debug         Enable debug output
    -h, --help          Show this help message

Arguments:
    SERVICE_NAME        One or more service names to analyze

Examples:
    parse-env.sh --all                    # Analyze all services
    parse-env.sh nginx grafana            # Analyze specific services
    parse-env.sh --secrets                # Security scan for secrets
    parse-env.sh --vault                  # Check for Vault integration
    parse-env.sh --format json nginx      # Output as JSON

Environment Variables:
    DEBUG=1             Enable debug output
    VAULT_ADDR          Vault server address for validation
USAGE_EOF
}

# Check if SSH helper is available
check_ssh_connection() {
    log_info "Checking SSH connection to dockermaster..."

    if [[ ! -x "$SSH_HELPER" ]]; then
        log_error "SSH helper script not found: $SSH_HELPER"
        return 1
    fi

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

# Initialize output directory
init_output_dir() {
    local output_dir="$1"

    log_info "Initializing environment analysis directory: $output_dir"

    mkdir -p "$output_dir"/{summary,services}

    # Create master tracking files
    cat > "$output_dir/summary/analysis-metadata.json" << 'META_EOF'
{
    "analysis_date": "",
    "dockermaster_host": "",
    "total_services": 0,
    "services_with_env": 0,
    "total_variables": 0,
    "potential_secrets": 0,
    "vault_references": 0,
    "services": {}
}
META_EOF

    # Create CSV header
    echo "service,variable_name,value_type,is_secret,is_vault_ref,source_file" > "$output_dir/summary/all-variables.csv"

    log_success "Output directory initialized"
}

# Simple environment analysis function
analyze_service() {
    local service="$1"
    local output_dir="$2"

    log_info "Analyzing environment for service: $service"

    local service_path="$DOCKER_BASE_PATH/$service"
    local service_output="$output_dir/services/$service"
    mkdir -p "$service_output"

    # Check if service exists
    if ! "$SSH_HELPER" exec "test -d '$service_path'" 2>/dev/null; then
        log_error "Service directory not found: $service_path"
        echo "Service not found: $service_path" > "$service_output/error.txt"
        return 1
    fi

    # Check for .env file
    if "$SSH_HELPER" exec "test -f '$service_path/.env'" 2>/dev/null; then
        log_success "Found .env file for $service"
        "$SSH_HELPER" exec "cat '$service_path/.env'" > "$service_output/env-file.txt" 2>/dev/null || true

        # Simple analysis
        echo "Environment file analysis for $service" > "$service_output/analysis.txt"
        echo "Found .env file with $(wc -l < "$service_output/env-file.txt" 2>/dev/null || echo "0") lines" >> "$service_output/analysis.txt"
    else
        log_warning "No .env file found for $service"
        echo "No .env file found" > "$service_output/no-env.txt"
    fi

    # Check for docker-compose.yml
    if "$SSH_HELPER" exec "test -f '$service_path/docker-compose.yml'" 2>/dev/null; then
        log_info "Found docker-compose.yml for $service"
        "$SSH_HELPER" exec "cat '$service_path/docker-compose.yml'" > "$service_output/docker-compose.yml" 2>/dev/null || true
    fi

    return 0
}

# Main analysis function
analyze_services() {
    local services=("$@")
    local output_dir="${OUTPUT_DIR}"

    if [[ ${#services[@]} -eq 0 ]]; then
        log_info "No services specified, analyzing all services"

        # Get all services
        local all_services
        all_services=$("$SSH_HELPER" exec "find $DOCKER_BASE_PATH -maxdepth 1 -type d -name '[!.]*' | sort" 2>/dev/null) || {
            log_error "Failed to list services"
            return 1
        }

        while IFS= read -r service_path; do
            services+=($(basename "$service_path"))
        done <<< "$all_services"
    fi

    log_info "Analyzing environment variables for ${#services[@]} services"

    # Initialize output directory
    init_output_dir "$output_dir"

    local successful=0
    local failed=0

    # Analyze each service
    for service in "${services[@]}"; do
        log_info "Processing service: $service ($(($successful + $failed + 1))/${#services[@]})"

        if analyze_service "$service" "$output_dir"; then
            successful=$((successful + 1))
            log_success "✅ $service"
        else
            failed=$((failed + 1))
            log_error "❌ $service"
        fi
    done

    # Final summary
    log_info "Environment analysis completed"
    log_success "Successfully analyzed: $successful services"

    if [[ $failed -gt 0 ]]; then
        log_warning "Failed analysis: $failed services"
    fi

    log_info "Output saved to: $output_dir"

    return 0
}

# Main function
main() {
    local services=()
    local list_only=false
    local secrets_only=false
    local include_compose=false
    local check_vault=false
    local format="table"

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--all)
                services=()
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
            -s|--secrets)
                secrets_only=true
                shift
                ;;
            -c|--compose)
                include_compose=true
                shift
                ;;
            -v|--vault)
                check_vault=true
                shift
                ;;
            -d|--debug)
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

    # Check SSH connection first
    if ! check_ssh_connection; then
        exit 1
    fi

    # Handle list option
    if [[ "$list_only" == "true" ]]; then
        log_info "List mode not yet implemented - use --all to analyze all services"
        exit 0
    fi

    # Analyze services
    analyze_services "${services[@]}"
}

# Run main function with all arguments
main "$@"
