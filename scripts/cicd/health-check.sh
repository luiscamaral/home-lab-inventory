#!/bin/bash
# Dockermaster Service Health Check Script
# This script provides comprehensive health checking for dockermaster services

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_PATH="${DEPLOY_PATH:-/nfs/dockermaster/docker}"
VAULT_ADDR="${VAULT_ADDR:-http://vault.d.lcamaral.com}"
PORTAINER_URL="${PORTAINER_URL:-https://192.168.59.2:9000}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-30}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

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

log_debug() {
    if [[ "$LOG_LEVEL" == "DEBUG" ]]; then
        echo -e "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
    fi
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS] [SERVICE_NAME...]

Perform comprehensive health checks on dockermaster services.

ARGUMENTS:
    SERVICE_NAME    One or more service names to check (default: all services)

OPTIONS:
    -h, --help                    Show this help message
    -v, --verbose                 Enable verbose output with DEBUG logging
    -q, --quiet                   Suppress all output except errors
    -j, --json                    Output results in JSON format
    -f, --format FORMAT           Output format: table, json, summary (default: table)
    -t, --timeout SECONDS         Health check timeout per service (default: $HEALTH_TIMEOUT)
    -d, --detailed                Include detailed metrics and resource usage
    -c, --continuous              Continuous monitoring mode (run indefinitely)
    -i, --interval SECONDS        Interval for continuous mode (default: 60)
    --threshold-cpu PERCENT       CPU usage threshold for warnings (default: 80)
    --threshold-memory PERCENT    Memory usage threshold for warnings (default: 85)
    --no-network-check            Skip network connectivity tests
    --no-endpoint-check           Skip service-specific endpoint checks
    --exit-on-unhealthy           Exit with error code if any service is unhealthy

OUTPUT FORMATS:
    table      Human-readable table format (default)
    json       JSON output suitable for parsing
    summary    Brief summary with counts only

EXAMPLES:
    $0                           # Check all services in table format
    $0 vault portainer          # Check specific services
    $0 -j --detailed            # JSON output with detailed metrics
    $0 -c -i 30                 # Continuous monitoring every 30 seconds
    $0 --format summary         # Brief summary only

EXIT CODES:
    0    All services healthy
    1    Some services unhealthy (when --exit-on-unhealthy)
    2    Script error
    10   Invalid arguments
EOF
}

# Global variables
VERBOSE=false
QUIET=false
OUTPUT_FORMAT="table"
DETAILED=false
CONTINUOUS=false
INTERVAL=60
THRESHOLD_CPU=80
THRESHOLD_MEMORY=85
NETWORK_CHECK=true
ENDPOINT_CHECK=true
EXIT_ON_UNHEALTHY=false
SERVICES=()

# Parse command line arguments
parse_args() {
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
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -j|--json)
                OUTPUT_FORMAT="json"
                shift
                ;;
            -f|--format)
                OUTPUT_FORMAT="$2"
                case "$OUTPUT_FORMAT" in
                    table|json|summary) ;;
                    *) log_error "Invalid format: $OUTPUT_FORMAT"; exit 10 ;;
                esac
                shift 2
                ;;
            -t|--timeout)
                HEALTH_TIMEOUT="$2"
                shift 2
                ;;
            -d|--detailed)
                DETAILED=true
                shift
                ;;
            -c|--continuous)
                CONTINUOUS=true
                shift
                ;;
            -i|--interval)
                INTERVAL="$2"
                shift 2
                ;;
            --threshold-cpu)
                THRESHOLD_CPU="$2"
                shift 2
                ;;
            --threshold-memory)
                THRESHOLD_MEMORY="$2"
                shift 2
                ;;
            --no-network-check)
                NETWORK_CHECK=false
                shift
                ;;
            --no-endpoint-check)
                ENDPOINT_CHECK=false
                shift
                ;;
            --exit-on-unhealthy)
                EXIT_ON_UNHEALTHY=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                exit 10
                ;;
            *)
                SERVICES+=("$1")
                shift
                ;;
        esac
    done
}

# Discover available services
discover_services() {
    log_debug "Discovering available services..."

    local discovered_services=()

    for compose_file in "$DEPLOY_PATH"/*/docker-compose.yml "$DEPLOY_PATH"/*/docker-compose.yaml; do
        if [[ -f "$compose_file" ]]; then
            local service_name
            service_name=$(basename "$(dirname "$compose_file")")

            # Check if service has running containers
            if (cd "$(dirname "$compose_file")" && docker compose ps --services --filter "status=running" | grep -q .); then
                discovered_services+=("$service_name")
                log_debug "Found running service: $service_name"
            else
                log_debug "Service not running: $service_name"
            fi
        fi
    done

    if [[ ${#SERVICES[@]} -eq 0 ]]; then
        SERVICES=("${discovered_services[@]}")
        log_debug "Using all discovered services: ${SERVICES[*]}"
    else
        # Validate provided services exist
        local valid_services=()
        for service in "${SERVICES[@]}"; do
            if [[ " ${discovered_services[*]} " =~ " ${service} " ]]; then
                valid_services+=("$service")
            else
                log_warn "Service not found or not running: $service"
            fi
        done
        SERVICES=("${valid_services[@]}")
    fi

    if [[ ${#SERVICES[@]} -eq 0 ]]; then
        log_error "No services found for health checking"
        exit 2
    fi
}

# Check container health
check_container_health() {
    local service_name="$1"
    local service_dir="$DEPLOY_PATH/$service_name"

    log_debug "Checking container health for $service_name"

    if [[ ! -d "$service_dir" ]]; then
        echo "directory_missing"
        return 1
    fi

    cd "$service_dir"

    # Get container information
    local containers_data
    containers_data=$(docker compose ps --format json 2>/dev/null || echo "[]")

    if [[ "$containers_data" == "[]" || -z "$containers_data" ]]; then
        echo "no_containers"
        return 1
    fi

    local running_count=0
    local total_count=0
    local unhealthy_containers=()

    while IFS= read -r container_line; do
        if [[ -n "$container_line" ]]; then
            local container_name state health
            container_name=$(echo "$container_line" | jq -r '.Name')
            state=$(echo "$container_line" | jq -r '.State')
            health=$(echo "$container_line" | jq -r '.Health // "no-healthcheck"')

            ((total_count++))

            if [[ "$state" == "running" ]]; then
                ((running_count++))

                if [[ "$health" == "unhealthy" ]]; then
                    unhealthy_containers+=("$container_name")
                fi
            fi

            log_debug "Container $container_name: state=$state, health=$health"
        fi
    done <<< "$(echo "$containers_data" | jq -c '.[]')"

    # Determine overall health status
    if [[ $running_count -eq $total_count ]] && [[ $total_count -gt 0 ]] && [[ ${#unhealthy_containers[@]} -eq 0 ]]; then
        echo "healthy"
    elif [[ $running_count -gt 0 ]]; then
        if [[ ${#unhealthy_containers[@]} -gt 0 ]]; then
            echo "unhealthy"
        else
            echo "degraded"
        fi
    else
        echo "down"
    fi

    # Store container info for detailed output
    if [[ "$DETAILED" == "true" ]]; then
        echo "$running_count:$total_count:${unhealthy_containers[*]}" > "/tmp/health-check-$service_name-containers.tmp"
    fi
}

# Get resource usage metrics
get_resource_metrics() {
    local service_name="$1"

    if [[ "$DETAILED" != "true" ]]; then
        echo "{}"
        return 0
    fi

    log_debug "Getting resource metrics for $service_name"

    local service_dir="$DEPLOY_PATH/$service_name"
    cd "$service_dir"

    # Get container names for this service
    local container_names
    container_names=$(docker compose ps --format json | jq -r '.Name' | tr '\n' ' ')

    if [[ -z "$container_names" ]]; then
        echo "{}"
        return 0
    fi

    # Get resource stats
    local stats_json="{}"
    local total_cpu=0
    local total_memory_used=0
    local total_memory_limit=0
    local container_count=0

    for container in $container_names; do
        if [[ -n "$container" ]]; then
            local stats
            stats=$(docker stats "$container" --no-stream --format json 2>/dev/null || echo "{}")

            if [[ "$stats" != "{}" ]]; then
                local cpu_percent memory_usage memory_limit
                cpu_percent=$(echo "$stats" | jq -r '.CPUPerc' | sed 's/%//' || echo "0")
                memory_usage=$(echo "$stats" | jq -r '.MemUsage' | cut -d'/' -f1 | sed 's/[^0-9.]//g' || echo "0")
                memory_limit=$(echo "$stats" | jq -r '.MemUsage' | cut -d'/' -f2 | sed 's/[^0-9.]//g' || echo "0")

                # Convert to numbers (remove any non-numeric chars)
                cpu_percent=$(echo "$cpu_percent" | sed 's/[^0-9.]//g')

                if [[ -n "$cpu_percent" ]] && [[ "$cpu_percent" != "0" ]]; then
                    total_cpu=$(echo "$total_cpu + $cpu_percent" | bc 2>/dev/null || echo "$total_cpu")
                fi

                ((container_count++))

                log_debug "Container $container: CPU=$cpu_percent%, Memory=$memory_usage/$memory_limit"
            fi
        fi
    done

    # Calculate averages
    local avg_cpu=0
    if [[ $container_count -gt 0 ]] && command -v bc &> /dev/null; then
        avg_cpu=$(echo "scale=2; $total_cpu / $container_count" | bc 2>/dev/null || echo "0")
    fi

    # Build metrics JSON
    stats_json=$(jq -n \
        --arg cpu "$avg_cpu" \
        --arg containers "$container_count" \
        '{
            "cpu_percent": ($cpu | tonumber),
            "container_count": ($containers | tonumber),
            "timestamp": now
        }')

    echo "$stats_json"
}

# Check service-specific endpoints
check_service_endpoint() {
    local service_name="$1"

    if [[ "$ENDPOINT_CHECK" != "true" ]]; then
        echo "skipped"
        return 0
    fi

    log_debug "Checking service endpoint for $service_name"

    case "$service_name" in
        "vault")
            if timeout "$HEALTH_TIMEOUT" curl -s -f "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
                echo "healthy"
            else
                echo "unhealthy"
            fi
            ;;
        "portainer")
            if timeout "$HEALTH_TIMEOUT" curl -s -f -k "$PORTAINER_URL/api/status" >/dev/null 2>&1; then
                echo "healthy"
            else
                echo "unhealthy"
            fi
            ;;
        "github-runner")
            local service_dir="$DEPLOY_PATH/$service_name"
            cd "$service_dir"
            local runner_logs
            runner_logs=$(docker compose logs --tail=10 2>/dev/null | grep -i "Listening for Jobs" || echo "")
            if [[ -n "$runner_logs" ]]; then
                echo "healthy"
            else
                echo "unhealthy"
            fi
            ;;
        *)
            echo "not_implemented"
            ;;
    esac
}

# Check network connectivity
check_network_connectivity() {
    local service_name="$1"

    if [[ "$NETWORK_CHECK" != "true" ]]; then
        echo "skipped"
        return 0
    fi

    log_debug "Checking network connectivity for $service_name"

    local service_dir="$DEPLOY_PATH/$service_name"
    cd "$service_dir"

    # Get first running container
    local container_name
    container_name=$(docker compose ps --format json | jq -r 'select(.State == "running") | .Name' | head -1)

    if [[ -z "$container_name" ]]; then
        echo "no_running_containers"
        return 1
    fi

    # Test external connectivity
    if timeout "$HEALTH_TIMEOUT" docker exec "$container_name" ping -c 1 -W 10 8.8.8.8 >/dev/null 2>&1; then
        echo "healthy"
    else
        echo "unhealthy"
    fi
}

# Perform comprehensive health check for a single service
health_check_service() {
    local service_name="$1"

    log_debug "Starting health check for $service_name"

    local result='{}'
    result=$(echo "$result" | jq --arg service "$service_name" --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .service = $service |
        .timestamp = $timestamp
    ')

    # Container health check
    local container_health
    container_health=$(check_container_health "$service_name")
    result=$(echo "$result" | jq --arg health "$container_health" '.container_health = $health')

    # Get container details if detailed mode
    if [[ "$DETAILED" == "true" ]] && [[ -f "/tmp/health-check-$service_name-containers.tmp" ]]; then
        local container_info
        container_info=$(cat "/tmp/health-check-$service_name-containers.tmp")
        IFS=':' read -r running total unhealthy <<< "$container_info"
        result=$(echo "$result" | jq \
            --arg running "$running" \
            --arg total "$total" \
            --arg unhealthy "$unhealthy" \
            '.containers = {running: ($running | tonumber), total: ($total | tonumber), unhealthy: $unhealthy}')
        rm -f "/tmp/health-check-$service_name-containers.tmp"
    fi

    # Resource metrics
    local metrics
    metrics=$(get_resource_metrics "$service_name")
    result=$(echo "$result" | jq --argjson metrics "$metrics" '.metrics = $metrics')

    # Service endpoint check
    local endpoint_health
    endpoint_health=$(check_service_endpoint "$service_name")
    result=$(echo "$result" | jq --arg endpoint "$endpoint_health" '.endpoint_health = $endpoint')

    # Network connectivity check
    local network_health
    network_health=$(check_network_connectivity "$service_name")
    result=$(echo "$result" | jq --arg network "$network_health" '.network_health = $network')

    # Determine overall health status
    local overall_status="healthy"
    if [[ "$container_health" == "down" ]] || [[ "$container_health" == "no_containers" ]] || [[ "$container_health" == "directory_missing" ]]; then
        overall_status="down"
    elif [[ "$container_health" == "unhealthy" ]] || [[ "$endpoint_health" == "unhealthy" ]] || [[ "$network_health" == "unhealthy" ]]; then
        overall_status="unhealthy"
    elif [[ "$container_health" == "degraded" ]] || [[ "$endpoint_health" == "degraded" ]]; then
        overall_status="degraded"
    fi

    result=$(echo "$result" | jq --arg status "$overall_status" '.overall_status = $status')

    log_debug "Health check completed for $service_name: $overall_status"

    echo "$result"
}

# Format and display results
display_results() {
    local results_json="$1"

    case "$OUTPUT_FORMAT" in
        "json")
            echo "$results_json" | jq .
            ;;
        "summary")
            local total healthy unhealthy degraded down
            total=$(echo "$results_json" | jq '.services | length')
            healthy=$(echo "$results_json" | jq '[.services[] | select(.overall_status == "healthy")] | length')
            unhealthy=$(echo "$results_json" | jq '[.services[] | select(.overall_status == "unhealthy")] | length')
            degraded=$(echo "$results_json" | jq '[.services[] | select(.overall_status == "degraded")] | length')
            down=$(echo "$results_json" | jq '[.services[] | select(.overall_status == "down")] | length')

            echo "Health Check Summary:"
            echo "  Total services: $total"
            echo "  Healthy: $healthy ✅"
            echo "  Degraded: $degraded ⚠️"
            echo "  Unhealthy: $unhealthy ❌"
            echo "  Down: $down 💀"
            ;;
        "table"|*)
            if [[ "$QUIET" == "true" ]]; then
                return 0
            fi

            echo
            echo "Dockermaster Service Health Check Report"
            echo "=========================================="
            echo "Timestamp: $(echo "$results_json" | jq -r '.timestamp')"
            echo

            # Table header
            if [[ "$DETAILED" == "true" ]]; then
                printf "%-20s %-12s %-12s %-12s %-10s %-15s\n" "Service" "Status" "Containers" "Endpoint" "Network" "CPU%"
                printf "%-20s %-12s %-12s %-12s %-10s %-15s\n" "--------" "-------" "-----------" "--------" "-------" "----"
            else
                printf "%-20s %-12s %-12s %-12s %-10s\n" "Service" "Status" "Containers" "Endpoint" "Network"
                printf "%-20s %-12s %-12s %-12s %-10s\n" "--------" "-------" "-----------" "--------" "-------"
            fi

            # Table rows
            echo "$results_json" | jq -r '.services[] |
                [.service, .overall_status, .container_health, .endpoint_health, .network_health] +
                (if .metrics then [(.metrics.cpu_percent | tostring)] else [""] end) |
                @tsv' | while IFS=$'\t' read -r service status containers endpoint network cpu; do

                # Status emoji
                local status_display="$status"
                case "$status" in
                    "healthy") status_display="✅ $status" ;;
                    "degraded") status_display="⚠️ $status" ;;
                    "unhealthy") status_display="❌ $status" ;;
                    "down") status_display="💀 $status" ;;
                esac

                if [[ "$DETAILED" == "true" ]]; then
                    printf "%-20s %-12s %-12s %-12s %-10s %-15s\n" "$service" "$status_display" "$containers" "$endpoint" "$network" "$cpu"
                else
                    printf "%-20s %-12s %-12s %-12s %-10s\n" "$service" "$status_display" "$containers" "$endpoint" "$network"
                fi
            done

            echo

            # Summary
            local total healthy unhealthy degraded down
            total=$(echo "$results_json" | jq '.services | length')
            healthy=$(echo "$results_json" | jq '[.services[] | select(.overall_status == "healthy")] | length')
            unhealthy=$(echo "$results_json" | jq '[.services[] | select(.overall_status == "unhealthy")] | length')
            degraded=$(echo "$results_json" | jq '[.services[] | select(.overall_status == "degraded")] | length')
            down=$(echo "$results_json" | jq '[.services[] | select(.overall_status == "down")] | length')

            echo "Summary: $total total, $healthy healthy, $degraded degraded, $unhealthy unhealthy, $down down"
            echo
            ;;
    esac
}

# Main health check execution
run_health_checks() {
    log_info "Running health checks for ${#SERVICES[@]} services: ${SERVICES[*]}"

    local all_results='{"timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'", "services": []}'
    local overall_healthy=true

    for service in "${SERVICES[@]}"; do
        log_debug "Checking service: $service"

        local service_result
        service_result=$(health_check_service "$service")

        # Add to results
        all_results=$(echo "$all_results" | jq --argjson service "$service_result" '.services += [$service]')

        # Check if service is unhealthy for exit code determination
        local service_status
        service_status=$(echo "$service_result" | jq -r '.overall_status')
        if [[ "$service_status" != "healthy" ]]; then
            overall_healthy=false
        fi

        # Log individual service status
        case "$service_status" in
            "healthy") log_success "✅ $service is healthy" ;;
            "degraded") log_warn "⚠️ $service is degraded" ;;
            "unhealthy") log_error "❌ $service is unhealthy" ;;
            "down") log_error "💀 $service is down" ;;
        esac
    done

    # Display results
    display_results "$all_results"

    # Return appropriate exit code
    if [[ "$EXIT_ON_UNHEALTHY" == "true" ]] && [[ "$overall_healthy" == "false" ]]; then
        return 1
    fi

    return 0
}

# Continuous monitoring mode
continuous_monitoring() {
    log_info "Starting continuous monitoring mode (interval: ${INTERVAL}s)"

    # Handle interrupts gracefully
    trap 'log_info "Stopping continuous monitoring..."; exit 0' SIGINT SIGTERM

    local iteration=0
    while true; do
        ((iteration++))

        if [[ "$QUIET" != "true" ]]; then
            echo "==================== Health Check #$iteration ===================="
        fi

        if ! run_health_checks; then
            if [[ "$EXIT_ON_UNHEALTHY" == "true" ]]; then
                log_error "Exiting due to unhealthy services (--exit-on-unhealthy)"
                exit 1
            fi
        fi

        if [[ "$QUIET" != "true" ]]; then
            echo
            log_info "Next check in ${INTERVAL}s... (Ctrl+C to stop)"
            echo
        fi

        sleep "$INTERVAL"
    done
}

# Main execution
main() {
    # Validate dependencies
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not available"
        exit 2
    fi

    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed"
        exit 2
    fi

    # Discover services
    discover_services

    if [[ ${#SERVICES[@]} -eq 0 ]]; then
        log_error "No services found for health checking"
        exit 2
    fi

    # Run health checks
    if [[ "$CONTINUOUS" == "true" ]]; then
        continuous_monitoring
    else
        run_health_checks
    fi
}

# Entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_args "$@"
    main
fi
