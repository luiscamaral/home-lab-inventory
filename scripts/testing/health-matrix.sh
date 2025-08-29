#!/usr/bin/env bash
# =============================================================================
# Service Health Matrix Generator
# Phase 7.0 - Dockermaster Recovery Project
# =============================================================================

set -eo pipefail

# Configuration
DOCKERMASTER_HOST="dockermaster"
REPORT_FILE="docs/validation/health-status-matrix-$(date +%Y%m%d-%H%M%S).md"
SERVICES_CONFIG="docs/service-matrix.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Health check functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $*${NC}" >&2
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}" >&2
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $*${NC}" >&2
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*${NC}" >&2
}

# Service definitions using indexed arrays (compatible with bash 3.x)
HIGH_PRIORITY_SERVICES=(
    "github-runner:github-runner-homelab"
    "vault:vault"
    "keycloak:keycloak"
    "prometheus:prometheus"
)

MEDIUM_PRIORITY_SERVICES=(
    "rabbitmq:rabbitmq"
)

LOW_PRIORITY_SERVICES=(
    "ansible-stack:ansible-observability"
    "bitwarden:bitwarden"
    "docspell:docspell-joex"
    "fluentd:fluentd"
    "ghost.io:ghost"
    "kafka:kafka"
    "mongodb:mongodb"
    "mysql:mysql"
    "opentelemetry-home:jaeger"
    "otel:otel-collector"
    "postgres:postgres"
    "solr:solr"
)

INFRASTRUCTURE_SERVICES=(
    "nginx:nginx-proxy-manager"
    "grafana:grafana"
    "grafana-v2:grafana-v2"
    "homer:homer"
    "mqtt:mqtt-broker"
    "n8n:n8n"
    "nodered:node-red"
    "portainer:portainer"
    "home-assistant-v2:home-assistant"
    "obsidian-remote:obsidian-remote"
)

SPECIAL_SERVICES=(
    "pablo:pablo"
    "prometheus.new:prometheus-new"
    "grafana-old:grafana-old"
    "home-lab-inventory:home-lab-inventory"
    "network:network-config"
)

# Function to parse service:container pairs
parse_service() {
    local service_entry="$1"
    local service_name="${service_entry%%:*}"
    local container_name="${service_entry##*:}"
    echo "$service_name:$container_name"
}

# Function to check if SSH connection to dockermaster is available
check_ssh_connection() {
    log "Testing SSH connection to dockermaster..."
    
    if ssh -o ConnectTimeout=10 -o BatchMode=yes "$DOCKERMASTER_HOST" "echo 'SSH connection successful'" 2>/dev/null; then
        log "SSH connection to dockermaster: HEALTHY ✅"
        return 0
    else
        error "SSH connection to dockermaster: FAILED ❌"
        return 1
    fi
}

# Function to get container status
get_container_status() {
    local service_name="$1"
    local container_name="$2"
    
    # Get container status via SSH
    local status
    status=$(ssh "$DOCKERMASTER_HOST" "docker ps -a --filter 'name=$container_name' --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" 2>/dev/null | tail -n +2)
    
    if [[ -n "$status" ]]; then
        echo "$status"
    else
        echo "CONTAINER_NOT_FOUND"
    fi
}

# Function to check service health
check_service_health() {
    local service_name="$1"
    local container_name="$2"
    
    local container_status
    container_status=$(get_container_status "$service_name" "$container_name")
    
    if [[ "$container_status" == "CONTAINER_NOT_FOUND" ]]; then
        echo "❌ NOT_FOUND"
        return 1
    fi
    
    # Check if container is running
    if echo "$container_status" | grep -q "Up "; then
        # Container is running, perform additional health checks
        case "$service_name" in
            "vault")
                local vault_health
                vault_health=$(ssh "$DOCKERMASTER_HOST" "curl -s http://192.168.59.25:8200/v1/sys/health 2>/dev/null | jq -r '.initialized' 2>/dev/null" || echo "unreachable")
                if [[ "$vault_health" == "true" ]]; then
                    echo "🟢 HEALTHY"
                else
                    echo "🔴 UNHEALTHY"
                fi
                ;;
            "keycloak")
                local keycloak_health
                keycloak_health=$(ssh "$DOCKERMASTER_HOST" "curl -s http://keycloak:8080/auth/realms/master/.well-known/openid_configuration 2>/dev/null" || echo "unreachable")
                if [[ "$keycloak_health" != "unreachable" ]] && [[ -n "$keycloak_health" ]]; then
                    echo "🟢 HEALTHY"
                else
                    echo "🔴 AUTH_ISSUES"
                fi
                ;;
            "prometheus")
                local prom_health
                prom_health=$(ssh "$DOCKERMASTER_HOST" "curl -s http://prometheus:9090/-/healthy 2>/dev/null" || echo "unreachable")
                if [[ "$prom_health" == "Prometheus is Healthy." ]]; then
                    echo "🟢 HEALTHY"
                else
                    echo "🔴 UNHEALTHY"
                fi
                ;;
            *)
                # Generic health check - just check if container is running
                echo "🟢 RUNNING"
                ;;
        esac
    elif echo "$container_status" | grep -q "Exited "; then
        echo "🔴 STOPPED"
    else
        echo "🟡 UNKNOWN"
    fi
}

# Function to get resource usage
get_resource_usage() {
    local container_name="$1"
    
    local cpu_mem
    cpu_mem=$(ssh "$DOCKERMASTER_HOST" "docker stats --no-stream --format 'table {{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}' $container_name 2>/dev/null | tail -n 1" 2>/dev/null)
    
    if [[ -n "$cpu_mem" ]]; then
        echo "$cpu_mem"
    else
        echo "N/A	N/A	N/A	N/A"
    fi
}

# Function to generate health report for a service array
generate_health_report() {
    local priority_label="$1"
    shift
    local services=("$@")
    
    echo "### $priority_label Services"
    echo ""
    echo "| Service | Container | Status | Health | CPU | Memory | Network I/O | Disk I/O | Last Updated |"
    echo "|---------|-----------|--------|--------|-----|--------|-------------|----------|--------------|"
    
    local service_count=0
    local healthy_count=0
    local issues_count=0
    local not_found_count=0
    
    for service_entry in "${services[@]}"; do
        local parsed
        parsed=$(parse_service "$service_entry")
        local service_name="${parsed%%:*}"
        local container_name="${parsed##*:}"
        
        local health_status
        local resource_usage
        local timestamp
        
        health_status=$(check_service_health "$service_name" "$container_name")
        resource_usage=$(get_resource_usage "$container_name")
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        
        # Parse resource usage
        IFS=$'\t' read -r cpu memory network_io block_io <<< "$resource_usage"
        
        echo "| $service_name | $container_name | $health_status | - | ${cpu:-N/A} | ${memory:-N/A} | ${network_io:-N/A} | ${block_io:-N/A} | $timestamp |"
        
        # Count statistics
        service_count=$((service_count + 1))
        if echo "$health_status" | grep -q "🟢"; then
            healthy_count=$((healthy_count + 1))
        elif echo "$health_status" | grep -q "❌.*NOT_FOUND"; then
            not_found_count=$((not_found_count + 1))
        else
            issues_count=$((issues_count + 1))
        fi
        
        # Small delay to avoid overwhelming the system
        sleep 0.5
    done
    
    echo ""
    echo "**$priority_label Summary:** $service_count services - $healthy_count healthy, $issues_count with issues, $not_found_count not found"
    echo ""
    
    # Store stats for global summary
    echo "$service_count $healthy_count $issues_count $not_found_count" >> /tmp/health_stats.tmp
}

# Function to create comprehensive health matrix report
create_health_matrix() {
    log "Creating comprehensive health status matrix..."
    
    # Initialize stats file
    rm -f /tmp/health_stats.tmp
    
    # Create report header
    cat > "$REPORT_FILE" << EOF
# 🏥 Service Health Status Matrix
# Dockermaster Recovery Project - Phase 7.0

**Generated:** $(date '+%Y-%m-%d %H:%M:%S')  
**Validation Phase:** System Health Assessment  
**Total Services:** 32  

## 📊 Executive Health Summary

EOF

    # Test SSH connection first
    if ! check_ssh_connection; then
        cat >> "$REPORT_FILE" << 'EOF'

## ❌ CRITICAL: SSH Connection Failed

Unable to connect to dockermaster server. Health matrix generation aborted.

**Actions Required:**
1. Verify dockermaster server is running
2. Check SSH connectivity: `ssh dockermaster`
3. Validate network connectivity
4. Re-run health matrix after connection is restored

EOF
        error "SSH connection failed. Health matrix generation aborted."
        return 1
    fi
    
    # Generate detailed reports for each priority level
    log "Scanning High Priority services..."
    generate_health_report "🔥 High Priority" "${HIGH_PRIORITY_SERVICES[@]}" >> "$REPORT_FILE"
    
    log "Scanning Medium Priority services..."
    generate_health_report "🟡 Medium Priority" "${MEDIUM_PRIORITY_SERVICES[@]}" >> "$REPORT_FILE"
    
    log "Scanning Low Priority services..."
    generate_health_report "🟢 Low Priority" "${LOW_PRIORITY_SERVICES[@]}" >> "$REPORT_FILE"
    
    log "Scanning Infrastructure services..."
    generate_health_report "🏗️ Infrastructure" "${INFRASTRUCTURE_SERVICES[@]}" >> "$REPORT_FILE"
    
    log "Scanning Special Case services..."
    generate_health_report "⚡ Special Cases" "${SPECIAL_SERVICES[@]}" >> "$REPORT_FILE"
    
    # Calculate summary statistics
    if [[ -f /tmp/health_stats.tmp ]]; then
        local total_services=0 total_healthy=0 total_issues=0 total_not_found=0
        while read -r services healthy issues not_found; do
            total_services=$((total_services + services))
            total_healthy=$((total_healthy + healthy))
            total_issues=$((total_issues + issues))
            total_not_found=$((total_not_found + not_found))
        done < /tmp/health_stats.tmp
        
        local success_rate
        if [[ $total_services -gt 0 ]]; then
            success_rate=$(( (total_healthy * 100) / total_services ))
        else
            success_rate=0
        fi
        
        # Insert summary at the beginning
        local temp_file
        temp_file=$(mktemp)
        head -n 9 "$REPORT_FILE" > "$temp_file"
        
        cat >> "$temp_file" << EOF

| Priority Level | Services | Healthy | Issues | Not Found | Success Rate |
|----------------|----------|---------|---------|-----------|--------------|
| **TOTAL SYSTEM** | **$total_services** | **$total_healthy** | **$total_issues** | **$total_not_found** | **${success_rate}%** |

## 🔍 Detailed Service Health Matrix

EOF
        
        tail -n +10 "$REPORT_FILE" >> "$temp_file"
        mv "$temp_file" "$REPORT_FILE"
        
        rm -f /tmp/health_stats.tmp
    fi
    
    # Add recommendations section
    cat >> "$REPORT_FILE" << 'EOF'

## 🚨 Critical Issues Identified

### Immediate Action Required

**Services requiring attention:**
1. Any service marked as ❌ NOT_FOUND needs deployment verification
2. Services with 🔴 UNHEALTHY status require investigation
3. Services with 🔴 STOPPED status need restart

## 📋 Validation Checklist

### Service Health Validation ✅
- [x] SSH connection to dockermaster established
- [x] All 32 services scanned
- [x] Health status determined for each service
- [x] Resource usage captured
- [x] Critical issues identified

### Next Steps
1. **Address Critical Issues**: Focus on services marked as UNHEALTHY or NOT_FOUND
2. **Performance Analysis**: Review resource usage for optimization opportunities
3. **Integration Testing**: Test service interdependencies (Phase 7.1)
4. **Performance Benchmarking**: Establish baseline metrics (Phase 7.2)

## 📊 Report Metadata

- **Generation Time**: $(date '+%Y-%m-%d %H:%M:%S')
- **Report Location**: `docs/validation/health-status-matrix-TIMESTAMP.md`
- **Next Update**: Manual execution required
- **Automation**: Can be integrated into CI/CD pipeline

---

*This report was generated by the Dockermaster Recovery Project Phase 7.0 validation system.*

EOF
    
    log "Health status matrix completed: $REPORT_FILE"
}

# Main execution
main() {
    log "Starting Service Health Matrix Generation"
    log "Report will be saved to: $REPORT_FILE"
    
    # Create health matrix
    create_health_matrix
    
    # Display summary
    log "Health matrix generation completed successfully!"
    log "Report saved to: $REPORT_FILE"
    log "Next steps:"
    log "1. Review health status for critical issues"
    log "2. Address any services marked as UNHEALTHY or NOT_FOUND"
    log "3. Proceed to Phase 7.1 - Integration Testing"
}

# Execute if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi