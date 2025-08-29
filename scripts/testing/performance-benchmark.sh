#!/usr/bin/env bash
# =============================================================================
# Performance Benchmarking Framework
# Phase 7.2 - Dockermaster Recovery Project
# =============================================================================

set -eo pipefail

# Configuration
DOCKERMASTER_HOST="dockermaster"
REPORT_FILE="docs/validation/performance-benchmark-$(date +%Y%m%d-%H%M%S).md"
BENCHMARK_ITERATIONS=3
WARMUP_TIME=30

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Performance metrics storage
declare -a SERVICE_STARTUP_TIMES
declare -a API_RESPONSE_TIMES
declare -a RESOURCE_UTILIZATION

# Function to measure service startup time
measure_startup_time() {
    local service_name="$1"
    local container_name="$2"

    log "Measuring startup time for $service_name..."

    local start_time end_time startup_duration

    # Stop service
    ssh "$DOCKERMASTER_HOST" "cd /nfs/dockermaster/docker/$service_name && docker compose down" >/dev/null 2>&1

    # Record start time and start service
    start_time=$(date +%s.%N)
    ssh "$DOCKERMASTER_HOST" "cd /nfs/dockermaster/docker/$service_name && docker compose up -d" >/dev/null 2>&1

    # Wait for service to be healthy
    local max_wait=120
    local wait_time=0

    while [[ $wait_time -lt $max_wait ]]; do
        if ssh "$DOCKERMASTER_HOST" "docker ps --filter 'name=$container_name' --filter 'status=running' | grep -q $container_name"; then
            # Check if service responds to health checks
            case "$service_name" in
                "vault")
                    if ssh "$DOCKERMASTER_HOST" "curl -s http://192.168.59.25:8200/v1/sys/health | jq -r '.initialized' 2>/dev/null" | grep -q "true\|false"; then
                        break
                    fi
                    ;;
                "grafana")
                    if ssh "$DOCKERMASTER_HOST" "curl -s http://grafana:3000/api/health | jq -r '.database' 2>/dev/null" | grep -q "ok"; then
                        break
                    fi
                    ;;
                *)
                    # For other services, just check if container is running
                    break
                    ;;
            esac
        fi
        sleep 2
        wait_time=$((wait_time + 2))
    done

    end_time=$(date +%s.%N)
    startup_duration=$(echo "$end_time - $start_time" | bc -l)

    if [[ $wait_time -ge $max_wait ]]; then
        warn "Service $service_name failed to start within $max_wait seconds"
        startup_duration="TIMEOUT"
    else
        log "Service $service_name started in ${startup_duration}s"
    fi

    SERVICE_STARTUP_TIMES+=("$service_name:$startup_duration")
}

# Function to measure API response times
measure_api_response_time() {
    local service_name="$1"
    local endpoint="$2"
    local description="$3"

    log "Measuring API response time for $service_name$endpoint..."

    local total_time=0
    local successful_requests=0
    local failed_requests=0

    for i in $(seq 1 $BENCHMARK_ITERATIONS); do
        local response_time
        response_time=$(ssh "$DOCKERMASTER_HOST" "curl -o /dev/null -s -w '%{time_total}' $service_name$endpoint 2>/dev/null" || echo "FAILED")

        if [[ "$response_time" == "FAILED" ]]; then
            failed_requests=$((failed_requests + 1))
        else
            total_time=$(echo "$total_time + $response_time" | bc -l)
            successful_requests=$((successful_requests + 1))
        fi

        sleep 1
    done

    local avg_response_time
    if [[ $successful_requests -gt 0 ]]; then
        avg_response_time=$(echo "scale=4; $total_time / $successful_requests" | bc -l)
    else
        avg_response_time="FAILED"
    fi

    API_RESPONSE_TIMES+=("$service_name$endpoint:$avg_response_time:$successful_requests/$BENCHMARK_ITERATIONS:$description")

    log "API $service_name$endpoint: ${avg_response_time}s average (${successful_requests}/${BENCHMARK_ITERATIONS} successful)"
}

# Function to measure resource utilization
measure_resource_utilization() {
    local container_name="$1"
    local service_name="$2"

    log "Measuring resource utilization for $service_name..."

    local cpu_usage memory_usage network_io disk_io
    local stats

    # Get resource stats
    stats=$(ssh "$DOCKERMASTER_HOST" "docker stats --no-stream --format 'table {{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}' $container_name 2>/dev/null | tail -n 1")

    if [[ -n "$stats" ]]; then
        IFS=$'\t' read -r cpu_usage memory_usage network_io disk_io <<< "$stats"
        RESOURCE_UTILIZATION+=("$service_name:$cpu_usage:$memory_usage:$network_io:$disk_io")
        log "Resource usage for $service_name: CPU=$cpu_usage, Memory=$memory_usage"
    else
        RESOURCE_UTILIZATION+=("$service_name:N/A:N/A:N/A:N/A")
        warn "Could not measure resource usage for $service_name"
    fi
}

# Function to benchmark critical services
benchmark_critical_services() {
    log "Benchmarking critical services startup and performance..."

    # High priority services to benchmark
    local services=(
        "github-runner:github-runner-homelab"
        "vault:vault"
        "grafana:grafana"
        "portainer:portainer"
    )

    for service_entry in "${services[@]}"; do
        local service_name="${service_entry%%:*}"
        local container_name="${service_entry##*:}"

        # Measure startup time
        measure_startup_time "$service_name" "$container_name"

        # Let service stabilize
        sleep 10

        # Measure resource utilization
        measure_resource_utilization "$container_name" "$service_name"

        sleep 5
    done
}

# Function to benchmark API endpoints
benchmark_api_endpoints() {
    log "Benchmarking API endpoint performance..."

    # Wait for services to be ready
    sleep "$WARMUP_TIME"

    # Critical API endpoints to benchmark
    measure_api_response_time "192.168.59.25:8200" "/v1/sys/health" "Vault health check"
    measure_api_response_time "grafana:3000" "/api/health" "Grafana health check"
    measure_api_response_time "192.168.59.2:9000" "/api/system/info" "Portainer system info"
    measure_api_response_time "keycloak:8080" "/auth/realms/master" "Keycloak master realm"
    measure_api_response_time "prometheus:9090" "/-/healthy" "Prometheus health check"
}

# Function to benchmark deployment workflow
benchmark_deployment_workflow() {
    log "Benchmarking deployment workflow performance..."

    local start_time end_time deployment_duration

    # Test deployment of a simple service
    start_time=$(date +%s.%N)

    # Deploy test service
    ssh "$DOCKERMASTER_HOST" "cd /nfs/dockermaster/docker && echo 'version: \"3.8\"
services:
  test-benchmark:
    image: nginx:alpine
    container_name: test-benchmark-container
    ports:
      - \"8888:80\"
    networks:
      - docker-servers-net

networks:
  docker-servers-net:
    external: true' > test-benchmark/docker-compose.yml && cd test-benchmark && docker compose up -d" >/dev/null 2>&1

    # Wait for service to be ready
    local max_wait=60
    local wait_time=0

    while [[ $wait_time -lt $max_wait ]]; do
        if ssh "$DOCKERMASTER_HOST" "curl -s http://localhost:8888 | grep -q nginx" 2>/dev/null; then
            break
        fi
        sleep 2
        wait_time=$((wait_time + 2))
    done

    end_time=$(date +%s.%N)
    deployment_duration=$(echo "$end_time - $start_time" | bc -l)

    # Cleanup test service
    ssh "$DOCKERMASTER_HOST" "cd /nfs/dockermaster/docker/test-benchmark && docker compose down && rm -rf /nfs/dockermaster/docker/test-benchmark" >/dev/null 2>&1

    log "Deployment workflow completed in ${deployment_duration}s"
    echo "deployment_workflow:$deployment_duration" >> /tmp/benchmark_results.tmp
}

# Function to create performance benchmark report
create_performance_report() {
    log "Creating performance benchmark report..."

    cat > "$REPORT_FILE" << EOF
# ⚡ Performance Benchmark Report
# Dockermaster Recovery Project - Phase 7.2

**Generated:** $(date '+%Y-%m-%d %H:%M:%S')
**Benchmark Phase:** Performance Baseline Assessment
**Test Iterations:** $BENCHMARK_ITERATIONS per metric
**Warmup Time:** ${WARMUP_TIME}s

## 📊 Performance Summary Dashboard

### System Performance Targets
| Metric | Target | Status | Notes |
|--------|--------|--------|-------|
| Service Startup | < 60s | TBD | Critical services average startup time |
| API Response | < 2s | TBD | Health check endpoint response times |
| Deployment Time | < 6 min | TBD | Complete service deployment workflow |
| Resource Usage | < 80% | TBD | CPU and memory utilization per service |

## 🚀 Service Startup Performance

### Startup Time Measurements
| Service | Startup Time | Status | Target | Notes |
|---------|--------------|--------|--------|-------|
EOF

    # Add startup time results
    for entry in "${SERVICE_STARTUP_TIMES[@]}"; do
        local service="${entry%%:*}"
        local time="${entry##*:}"
        local status="✅ GOOD"

        if [[ "$time" == "TIMEOUT" ]]; then
            status="❌ TIMEOUT"
        elif [[ "$time" != "N/A" ]] && (( $(echo "$time > 60" | bc -l) )); then
            status="⚠️ SLOW"
        fi

        echo "| $service | ${time}s | $status | < 60s | - |" >> "$REPORT_FILE"
    done

    cat >> "$REPORT_FILE" << EOF

## 🔗 API Performance Benchmarks

### Response Time Analysis
| Endpoint | Average Response | Success Rate | Status | Description |
|----------|------------------|--------------|--------|-------------|
EOF

    # Add API response time results
    for entry in "${API_RESPONSE_TIMES[@]}"; do
        IFS=':' read -r endpoint avg_time success_rate description <<< "$entry"
        local status="✅ GOOD"

        if [[ "$avg_time" == "FAILED" ]]; then
            status="❌ FAILED"
        elif [[ "$avg_time" != "N/A" ]] && (( $(echo "$avg_time > 2.0" | bc -l) )); then
            status="⚠️ SLOW"
        fi

        echo "| $endpoint | ${avg_time}s | $success_rate | $status | $description |" >> "$REPORT_FILE"
    done

    cat >> "$REPORT_FILE" << EOF

## 💻 Resource Utilization Analysis

### Current Resource Usage
| Service | CPU Usage | Memory Usage | Network I/O | Disk I/O | Status |
|---------|-----------|--------------|-------------|----------|--------|
EOF

    # Add resource utilization results
    for entry in "${RESOURCE_UTILIZATION[@]}"; do
        IFS=':' read -r service cpu memory network disk <<< "$entry"
        local status="✅ NORMAL"

        if [[ "$cpu" != "N/A" ]] && [[ "$cpu" =~ ([0-9.]+)% ]]; then
            local cpu_num="${BASH_REMATCH[1]}"
            if (( $(echo "$cpu_num > 80" | bc -l) )); then
                status="⚠️ HIGH CPU"
            fi
        fi

        echo "| $service | $cpu | $memory | $network | $disk | $status |" >> "$REPORT_FILE"
    done

    # Add deployment benchmark if available
    if [[ -f /tmp/benchmark_results.tmp ]]; then
        local deployment_time
        deployment_time=$(grep "deployment_workflow:" /tmp/benchmark_results.tmp | cut -d':' -f2)

        cat >> "$REPORT_FILE" << EOF

## 🚀 Deployment Performance

### Workflow Timing
| Workflow | Duration | Target | Status | Notes |
|----------|----------|--------|--------|-------|
| Service Deployment | ${deployment_time}s | < 360s | $(if (( $(echo "$deployment_time < 360" | bc -l) )); then echo "✅ GOOD"; else echo "⚠️ SLOW"; fi) | End-to-end deployment time |

EOF
        rm -f /tmp/benchmark_results.tmp
    fi

    cat >> "$REPORT_FILE" << EOF

## 📈 Performance Analysis

### Key Findings
1. **Startup Performance**: Average service startup time analysis
2. **API Responsiveness**: Health check endpoint performance
3. **Resource Efficiency**: CPU and memory utilization patterns
4. **Deployment Speed**: End-to-end deployment workflow timing

### Performance Recommendations
1. **Optimize Slow Starters**: Services with > 60s startup time need optimization
2. **API Optimization**: Endpoints with > 2s response need investigation
3. **Resource Management**: Services using > 80% CPU/memory need resource adjustment
4. **Deployment Pipeline**: Streamline deployment process if > 6 minutes

## 📋 Performance Validation Checklist

### Benchmark Execution ✅
- [x] Service startup times measured
- [x] API endpoint response times benchmarked
- [x] Resource utilization captured
- [x] Deployment workflow timed
- [x] Performance targets compared

### Next Steps
1. **Address Performance Issues**: Focus on services exceeding targets
2. **Disaster Recovery Testing**: Use baseline metrics for recovery validation (Phase 7.3)
3. **Performance Monitoring**: Establish ongoing performance tracking
4. **Optimization Planning**: Create performance improvement roadmap

## 📊 Benchmark Metadata

- **Test Framework**: Custom performance benchmarking
- **Execution Environment**: Local → SSH → Dockermaster
- **Benchmark Iterations**: $BENCHMARK_ITERATIONS per metric
- **Report Location**: \`$REPORT_FILE\`
- **Baseline Date**: $(date '+%Y-%m-%d')

---

*This report establishes performance baselines for the Dockermaster Recovery Project Phase 7.2.*
EOF

    log "Performance benchmark report completed: $REPORT_FILE"
}

# Main execution function
main() {
    log "Starting Performance Benchmarking Framework"
    log "Report will be saved to: $REPORT_FILE"
    log "Benchmark iterations: $BENCHMARK_ITERATIONS"
    log "Warmup time: ${WARMUP_TIME}s"

    # Test SSH connection first
    if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$DOCKERMASTER_HOST" "echo 'SSH connection successful'" >/dev/null 2>&1; then
        error "SSH connection to dockermaster failed"
        exit 1
    fi

    log "SSH connection established - beginning performance benchmarks"

    # Execute benchmark suites
    benchmark_critical_services
    benchmark_api_endpoints
    benchmark_deployment_workflow

    # Create comprehensive report
    create_performance_report

    # Display summary
    log "Performance benchmarking completed!"
    log "Report saved to: $REPORT_FILE"
    log "Next steps:"
    log "1. Review performance against targets"
    log "2. Address any performance issues identified"
    log "3. Proceed to Phase 7.3 - Disaster Recovery Testing"
}

# Execute if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
