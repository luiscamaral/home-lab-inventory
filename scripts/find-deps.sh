#!/bin/bash
# Find Service Dependencies Script
# Part of dockermaster-recovery documentation framework
# Created: 2025-08-28

set -euo pipefail

# Configuration
DOCKERMASTER_HOST="dockermaster"
DOCKER_BASE_PATH="/nfs/dockermaster/docker"
OUTPUT_DIR="$(dirname "$0")/../output/dependency-analysis"
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

log_dependency() {
    echo -e "${MAGENTA}[DEPENDENCY]${NC} $1" >&2
}

# Usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] [SERVICE_NAME...]

Analyze service dependencies in dockermaster infrastructure.

Options:
    -a, --all           Analyze all services (default if no services specified)
    -o, --output DIR    Output directory (default: $OUTPUT_DIR)
    -f, --format FORMAT Output format: graph, json, table, mermaid (default: table)
    -l, --list          List services and their immediate dependencies
    -t, --tree          Show dependency tree
    -r, --reverse       Show reverse dependencies (what depends on this service)
    -c, --circular      Detect circular dependencies
    -n, --network       Analyze network dependencies
    -v, --volumes       Analyze volume dependencies
    -d, --debug         Enable debug output
    -h, --help          Show this help message

Arguments:
    SERVICE_NAME        One or more service names to analyze

Examples:
    $SCRIPT_NAME --all                    # Analyze all services
    $SCRIPT_NAME nginx grafana            # Analyze specific services
    $SCRIPT_NAME --tree postgres          # Show postgres dependency tree
    $SCRIPT_NAME --reverse vault          # Show what depends on vault
    $SCRIPT_NAME --circular               # Check for circular dependencies
    $SCRIPT_NAME --format mermaid         # Generate Mermaid diagram
    
Output Structure:
    output/dependency-analysis/
    ├── services/
    │   ├── nginx/
    │   │   ├── dependencies.json
    │   │   ├── network-deps.txt
    │   │   └── volume-deps.txt
    ├── graphs/
    │   ├── dependency-graph.json
    │   ├── dependency-tree.txt
    │   ├── circular-deps.json
    │   └── mermaid-diagram.mmd
    ├── summary/
    │   ├── dependency-matrix.csv
    │   └── critical-path.json
    └── analysis-report.md

Dependency Types:
    - Network dependencies (linked services)
    - Volume dependencies (shared storage)
    - Environment dependencies (referenced services)
    - Database dependencies (connection strings)
    - External dependencies (external hosts/services)

Environment Variables:
    DEBUG=1             Enable debug output
    COMPOSE_TIMEOUT=30  Docker compose command timeout
EOF
}

# Initialize output directory
init_output_dir() {
    local output_dir="$1"
    
    log_info "Initializing dependency analysis directory: $output_dir"
    
    mkdir -p "$output_dir"/{services,graphs,summary}
    
    # Create master tracking files
    cat > "$output_dir/summary/analysis-metadata.json" << 'EOF'
{
    "analysis_date": "",
    "dockermaster_host": "",
    "total_services": 0,
    "dependency_relationships": 0,
    "circular_dependencies": 0,
    "isolated_services": 0,
    "critical_services": [],
    "services": {}
}
EOF
    
    # Create dependency matrix CSV
    echo "service,depends_on,dependency_type,criticality,status" > "$output_dir/summary/dependency-matrix.csv"
    
    log_success "Output directory initialized"
}

# Check SSH connection
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

# Extract dependencies from docker-compose.yml
extract_compose_dependencies() {
    local service="$1"
    local compose_file_path="$2"
    local output_dir="$3"
    
    log_debug "Extracting compose dependencies for $service"
    
    local service_output="$output_dir/services/$service"
    mkdir -p "$service_output"
    
    local dependencies_json="$service_output/dependencies.json"
    local network_deps="$service_output/network-deps.txt"
    local volume_deps="$service_output/volume-deps.txt"
    
    # Download compose file
    local temp_compose
    temp_compose=$(mktemp)
    
    if ! "$SSH_HELPER" exec "cat '$compose_file_path'" > "$temp_compose" 2>/dev/null; then
        log_warning "Could not read compose file: $compose_file_path"
        rm -f "$temp_compose"
        return 1
    fi
    
    # Initialize dependency structure
    cat > "$dependencies_json" << EOF
{
    "service": "$service",
    "analysis_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "compose_file": "$compose_file_path",
    "dependencies": {
        "depends_on": [],
        "links": [],
        "external_links": [],
        "networks": [],
        "volumes": [],
        "environment_refs": [],
        "database_connections": []
    },
    "provides": {
        "networks": [],
        "volumes": [],
        "services": []
    }
}
EOF
    
    echo "Network Dependencies for $service" > "$network_deps"
    echo "═══════════════════════════════════════════════════════════════════════" >> "$network_deps"
    echo "" >> "$network_deps"
    
    echo "Volume Dependencies for $service" > "$volume_deps"
    echo "═══════════════════════════════════════════════════════════════════════" >> "$volume_deps"
    echo "" >> "$volume_deps"
    
    # Parse compose file for dependencies
    local current_service=""
    local in_depends_on=false
    local in_links=false
    local in_networks=false
    local in_volumes=false
    local in_environment=false
    
    while IFS= read -r line; do
        # Remove leading/trailing whitespace
        line=$(echo "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        
        # Skip comments and empty lines
        if [[ "$line" =~ ^# ]] || [[ -z "$line" ]]; then
            continue
        fi
        
        # Detect service definitions
        if [[ "$line" =~ ^([a-zA-Z][a-zA-Z0-9_-]*):$ ]]; then
            current_service="${BASH_REMATCH[1]}"
            in_depends_on=false
            in_links=false
            in_networks=false
            in_volumes=false
            in_environment=false
        fi
        
        # Detect various dependency sections
        case "$line" in
            "depends_on:")
                in_depends_on=true
                ;;
            "links:")
                in_links=true
                ;;
            "networks:")
                in_networks=true
                ;;
            "volumes:")
                in_volumes=true
                ;;
            "environment:")
                in_environment=true
                ;;
            *)
                # Reset flags if we hit another section
                if [[ "$line" =~ ^[a-zA-Z_][a-zA-Z0-9_]*:$ ]]; then
                    in_depends_on=false
                    in_links=false
                    in_networks=false
                    in_volumes=false
                    in_environment=false
                fi
                ;;
        esac
        
        # Extract depends_on entries
        if [[ "$in_depends_on" == "true" ]] && [[ "$line" =~ ^-[[:space:]]*([a-zA-Z][a-zA-Z0-9_-]*) ]]; then
            local dep_service="${BASH_REMATCH[1]}"
            echo "$service,$dep_service,depends_on,high,active" >> "$output_dir/summary/dependency-matrix.csv"
            log_dependency "$service depends on $dep_service"
        fi
        
        # Extract links
        if [[ "$in_links" == "true" ]] && [[ "$line" =~ ^-[[:space:]]*([a-zA-Z][a-zA-Z0-9_-]*) ]]; then
            local linked_service="${BASH_REMATCH[1]}"
            echo "$service,$linked_service,link,medium,active" >> "$output_dir/summary/dependency-matrix.csv"
            echo "Linked to: $linked_service" >> "$network_deps"
        fi
        
        # Extract network references
        if [[ "$in_networks" == "true" ]] && [[ "$line" =~ ^-[[:space:]]*([a-zA-Z][a-zA-Z0-9_-]+) ]]; then
            local network_name="${BASH_REMATCH[1]}"
            echo "Uses network: $network_name" >> "$network_deps"
        fi
        
        # Extract volume references
        if [[ "$in_volumes" == "true" ]] && [[ "$line" =~ ^-[[:space:]]*([^:]+): ]]; then
            local volume_def="${BASH_REMATCH[1]}"
            echo "Volume dependency: $volume_def" >> "$volume_deps"
        fi
        
        # Extract environment-based dependencies
        if [[ "$in_environment" == "true" ]]; then
            # Look for database connection strings and service references
            if [[ "$line" =~ DATABASE_URL|DB_HOST|MYSQL_HOST|POSTGRES_HOST|REDIS_HOST|MONGO_HOST ]]; then
                local env_line=$(echo "$line" | sed 's/^-[[:space:]]*//')
                if [[ "$env_line" =~ ([A-Z_]+).*=.*(mysql|postgres|redis|mongo|vault|keycloak) ]]; then
                    local env_var="${BASH_REMATCH[1]}"
                    local referenced_service="${BASH_REMATCH[2]}"
                    echo "$service,$referenced_service,environment,high,active" >> "$output_dir/summary/dependency-matrix.csv"
                    log_dependency "$service references $referenced_service via $env_var"
                fi
            fi
        fi
        
    done < "$temp_compose"
    
    # Check for external links and networks
    if "$SSH_HELPER" exec "grep -E '(external_links|external.*true)' '$compose_file_path'" >/dev/null 2>&1; then
        echo "" >> "$network_deps"
        echo "External Dependencies:" >> "$network_deps"
        "$SSH_HELPER" exec "grep -E '(external_links|external.*true)' '$compose_file_path'" | while read -r ext_line; do
            echo "  $ext_line" >> "$network_deps"
        done
    fi
    
    rm -f "$temp_compose"
    log_debug "Compose dependencies extracted for $service"
    return 0
}

# Analyze runtime dependencies using docker inspect
analyze_runtime_dependencies() {
    local service="$1"
    local output_dir="$2"
    
    log_debug "Analyzing runtime dependencies for $service"
    
    local service_output="$output_dir/services/$service"
    local runtime_deps="$service_output/runtime-deps.txt"
    
    echo "Runtime Dependencies for $service" > "$runtime_deps"
    echo "═══════════════════════════════════════════════════════════════════════" >> "$runtime_deps"
    echo "Analysis Date: $(date)" >> "$runtime_deps"
    echo "" >> "$runtime_deps"
    
    # Check if containers are running
    local containers
    containers=$("$SSH_HELPER" exec "docker ps --format '{{.Names}}' | grep -E '^${service}[_-]|^${service}$'" 2>/dev/null || echo "")
    
    if [[ -z "$containers" ]]; then
        echo "Service containers not currently running" >> "$runtime_deps"
        log_warning "No running containers found for $service"
        return 0
    fi
    
    echo "Running Containers:" >> "$runtime_deps"
    while IFS= read -r container; do
        if [[ -n "$container" ]]; then
            echo "  - $container" >> "$runtime_deps"
            
            # Get container network information
            local networks
            networks=$("$SSH_HELPER" exec "docker inspect '$container' --format '{{range .NetworkSettings.Networks}}{{.NetworkID}} {{end}}' 2>/dev/null" || echo "")
            
            if [[ -n "$networks" ]]; then
                echo "    Networks: $networks" >> "$runtime_deps"
            fi
            
            # Check for linked containers (legacy)
            local links
            links=$("$SSH_HELPER" exec "docker inspect '$container' --format '{{.HostConfig.Links}}' 2>/dev/null" || echo "")
            
            if [[ -n "$links" ]] && [[ "$links" != "[]" ]] && [[ "$links" != "<no value>" ]]; then
                echo "    Links: $links" >> "$runtime_deps"
            fi
        fi
    done <<< "$containers"
    
    log_debug "Runtime dependencies analyzed for $service"
    return 0
}

# Build dependency graph
build_dependency_graph() {
    local output_dir="$1"
    local format="${2:-json}"
    
    log_info "Building dependency graph in $format format"
    
    local graph_file="$output_dir/graphs/dependency-graph.$format"
    
    case "$format" in
        "json")
            cat > "$graph_file" << 'EOF'
{
    "graph_type": "service_dependencies",
    "generated_date": "",
    "nodes": [],
    "edges": [],
    "clusters": [],
    "metadata": {
        "total_services": 0,
        "total_dependencies": 0,
        "isolated_services": [],
        "critical_services": []
    }
}
EOF
            ;;
        "mermaid")
            cat > "$graph_file" << 'EOF'
graph TD
    %% Dockermaster Service Dependencies
    %% Generated on DATE
    
    classDef database fill:#e1f5fe
    classDef webapp fill:#f3e5f5
    classDef infrastructure fill:#fff3e0
    classDef security fill:#ffebee
    
EOF
            ;;
        "dot")
            cat > "$graph_file" << 'EOF'
digraph dockermaster_dependencies {
    rankdir=TB;
    node [shape=box, style=filled];
    
    // Clusters for different service types
    subgraph cluster_database {
        label="Databases";
        color=lightblue;
        style=filled;
        fillcolor=lightcyan;
    }
    
    subgraph cluster_web {
        label="Web Services";
        color=lightgreen;
        style=filled;
        fillcolor=lightgreen;
    }
    
    subgraph cluster_infrastructure {
        label="Infrastructure";
        color=orange;
        style=filled;
        fillcolor=lightyellow;
    }
EOF
            ;;
    esac
    
    # Parse dependency matrix and build graph
    if [[ -f "$output_dir/summary/dependency-matrix.csv" ]]; then
        local nodes=()
        local edges=()
        
        # Extract unique services
        tail -n +2 "$output_dir/summary/dependency-matrix.csv" | cut -d',' -f1,2 | tr ',' '\n' | sort -u > /tmp/all_services.txt
        
        # Build nodes and edges based on format
        case "$format" in
            "mermaid")
                while IFS= read -r service; do
                    if [[ -n "$service" ]]; then
                        echo "    $service[$service]" >> "$graph_file"
                    fi
                done < /tmp/all_services.txt
                
                echo "" >> "$graph_file"
                
                # Add edges
                tail -n +2 "$output_dir/summary/dependency-matrix.csv" | while IFS=',' read -r service depends_on dep_type criticality status; do
                    local edge_style=""
                    case "$dep_type" in
                        "depends_on") edge_style="-->" ;;
                        "link") edge_style="-.->|link|" ;;
                        "environment") edge_style="==>" ;;
                        *) edge_style="-->" ;;
                    esac
                    
                    echo "    $service $edge_style $depends_on" >> "$graph_file"
                done
                ;;
        esac
        
        rm -f /tmp/all_services.txt
    fi
    
    log_success "Dependency graph created: $graph_file"
}

# Detect circular dependencies
detect_circular_dependencies() {
    local output_dir="$1"
    
    log_info "Detecting circular dependencies..."
    
    local circular_file="$output_dir/graphs/circular-deps.json"
    
    cat > "$circular_file" << 'EOF'
{
    "analysis_date": "",
    "circular_dependencies_found": false,
    "circular_paths": [],
    "analysis_details": ""
}
EOF
    
    # Simple circular dependency detection using dependency matrix
    if [[ ! -f "$output_dir/summary/dependency-matrix.csv" ]]; then
        log_warning "No dependency matrix found for circular dependency analysis"
        return 1
    fi
    
    local temp_deps
    temp_deps=$(mktemp)
    
    # Extract service relationships
    tail -n +2 "$output_dir/summary/dependency-matrix.csv" | cut -d',' -f1,2 | sort > "$temp_deps"
    
    local circular_found=false
    local circular_paths=()
    
    # Check for direct circular dependencies (A->B, B->A)
    while IFS=',' read -r service1 service2; do
        if grep -q "^$service2,$service1$" "$temp_deps"; then
            circular_found=true
            circular_paths+=("$service1 <-> $service2")
            log_warning "Circular dependency detected: $service1 <-> $service2"
        fi
    done < "$temp_deps"
    
    if [[ "$circular_found" == "true" ]]; then
        log_error "Circular dependencies found! This can cause deployment issues."
        
        # Update JSON with findings
        local current_date
        current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        
        sed -i.bak "s/\"analysis_date\": \"\"/\"analysis_date\": \"$current_date\"/" "$circular_file"
        sed -i.bak "s/\"circular_dependencies_found\": false/\"circular_dependencies_found\": true/" "$circular_file"
        rm -f "$circular_file.bak"
    else
        log_success "No circular dependencies detected ✅"
    fi
    
    rm -f "$temp_deps"
    return 0
}

# Generate dependency tree for a service
generate_dependency_tree() {
    local service="$1"
    local output_dir="$2"
    local max_depth="${3:-5}"
    
    log_info "Generating dependency tree for $service (max depth: $max_depth)"
    
    local tree_file="$output_dir/graphs/${service}-dependency-tree.txt"
    
    cat > "$tree_file" << EOF
Dependency Tree for $service
═══════════════════════════════════════════════════════════════════════
Generated: $(date)
Max Depth: $max_depth

$service
EOF
    
    # Recursive function to build tree
    local visited=()
    
    build_tree_recursive() {
        local current_service="$1"
        local depth="$2"
        local prefix="$3"
        
        # Prevent infinite recursion
        if [[ $depth -gt $max_depth ]]; then
            return
        fi
        
        # Check if already visited (circular dependency detection)
        for visited_service in "${visited[@]}"; do
            if [[ "$visited_service" == "$current_service" ]]; then
                echo "${prefix}└── $current_service [CIRCULAR REFERENCE]" >> "$tree_file"
                return
            fi
        done
        
        visited+=("$current_service")
        
        # Find dependencies for current service
        local deps
        deps=$(grep "^$current_service," "$output_dir/summary/dependency-matrix.csv" 2>/dev/null | cut -d',' -f2 || echo "")
        
        local dep_count=0
        if [[ -n "$deps" ]]; then
            dep_count=$(echo "$deps" | wc -l)
        fi
        
        local counter=0
        while IFS= read -r dep; do
            if [[ -n "$dep" ]]; then
                counter=$((counter + 1))
                local new_prefix
                
                if [[ $counter -eq $dep_count ]]; then
                    echo "${prefix}└── $dep" >> "$tree_file"
                    new_prefix="${prefix}    "
                else
                    echo "${prefix}├── $dep" >> "$tree_file"
                    new_prefix="${prefix}│   "
                fi
                
                # Recurse
                build_tree_recursive "$dep" $((depth + 1)) "$new_prefix"
            fi
        done <<< "$deps"
        
        # Remove from visited when backtracking
        visited=("${visited[@]/$current_service}")
    }
    
    # Build tree starting from root service
    build_tree_recursive "$service" 0 ""
    
    log_success "Dependency tree generated: $tree_file"
}

# Analyze a single service
analyze_service_dependencies() {
    local service="$1"
    local output_dir="$2"
    
    log_info "Analyzing dependencies for service: $service"
    
    local service_path="$DOCKER_BASE_PATH/$service"
    
    # Check if service exists
    if ! "$SSH_HELPER" exec "test -d '$service_path'" 2>/dev/null; then
        log_error "Service directory not found: $service_path"
        return 1
    fi
    
    # Analyze docker-compose.yml if it exists
    local compose_file="$service_path/docker-compose.yml"
    if "$SSH_HELPER" exec "test -f '$compose_file'" 2>/dev/null; then
        extract_compose_dependencies "$service" "$compose_file" "$output_dir"
    else
        log_warning "No docker-compose.yml found for $service"
    fi
    
    # Analyze runtime dependencies
    analyze_runtime_dependencies "$service" "$output_dir"
    
    log_success "Dependencies analyzed for $service"
    return 0
}

# Generate summary report
generate_dependency_report() {
    local output_dir="$1"
    
    log_info "Generating dependency analysis report..."
    
    local report_file="$output_dir/analysis-report.md"
    
    cat > "$report_file" << EOF
# Service Dependencies Analysis Report

**Generated:** $(date)  
**Dockermaster Host:** $DOCKERMASTER_HOST  
**Analysis Type:** Service Dependencies and Infrastructure Mapping

## 📊 Executive Summary

EOF
    
    # Calculate metrics
    local total_services
    total_services=$(find "$output_dir/services" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l || echo "0")
    
    local total_deps
    total_deps=$(tail -n +2 "$output_dir/summary/dependency-matrix.csv" 2>/dev/null | wc -l || echo "0")
    
    local unique_services
    unique_services=$(tail -n +2 "$output_dir/summary/dependency-matrix.csv" 2>/dev/null | cut -d',' -f1 | sort -u | wc -l || echo "0")
    
    cat >> "$report_file" << EOF
| Metric | Count |
|--------|-------|
| Services Analyzed | $total_services |
| Dependency Relationships | $total_deps |
| Services with Dependencies | $unique_services |
| Isolated Services | $((total_services - unique_services)) |

## 🔗 Dependency Analysis

### High-Level Architecture
EOF
    
    # Most connected services
    if [[ $total_deps -gt 0 ]]; then
        cat >> "$report_file" << EOF

**Most Connected Services:**
EOF
        tail -n +2 "$output_dir/summary/dependency-matrix.csv" | cut -d',' -f1 | sort | uniq -c | sort -nr | head -5 | while read -r count service; do
            echo "- **$service**: $count dependencies" >> "$report_file"
        done
        
        cat >> "$report_file" << EOF

**Critical Dependencies (High Criticality):**
EOF
        tail -n +2 "$output_dir/summary/dependency-matrix.csv" | grep ",high," | cut -d',' -f1,2 | while IFS=',' read -r service dep; do
            echo "- **$service** → $dep" >> "$report_file"
        done
    fi
    
    cat >> "$report_file" << EOF

## 🚨 Critical Findings

### Potential Issues
EOF
    
    # Check for circular dependencies
    if [[ -f "$output_dir/graphs/circular-deps.json" ]]; then
        if grep -q '"circular_dependencies_found": true' "$output_dir/graphs/circular-deps.json"; then
            cat >> "$report_file" << EOF
- ⚠️  **Circular dependencies detected** - Review deployment order
EOF
        else
            cat >> "$report_file" << EOF
- ✅ No circular dependencies found
EOF
        fi
    fi
    
    # Isolated services
    if [[ $((total_services - unique_services)) -gt 0 ]]; then
        cat >> "$report_file" << EOF
- 🔍 **Isolated services found** - May indicate unused or standalone services
EOF
    fi
    
    cat >> "$report_file" << EOF

### Recommendations

1. **Service Startup Order:**
   - Review dependency chains for proper initialization sequence
   - Implement health checks and wait conditions
   - Consider service mesh for complex topologies

2. **High Availability:**
   - Identify single points of failure
   - Implement redundancy for critical dependencies
   - Consider service clustering where appropriate

3. **Network Architecture:**
   - Review network segregation and security
   - Optimize service communication patterns
   - Consider microservices architecture principles

## 📁 Generated Files

- \`summary/dependency-matrix.csv\` - Complete dependency mapping
- \`graphs/dependency-graph.*\` - Visual dependency representations
- \`services/[service]/dependencies.json\` - Per-service dependency details
- \`graphs/circular-deps.json\` - Circular dependency analysis

## 🎯 Next Steps

1. Review identified circular dependencies
2. Optimize service startup sequences  
3. Implement proper health checks
4. Consider dependency injection patterns
5. Plan for service mesh implementation if needed

---
*Generated by dockermaster-recovery documentation framework*
EOF
    
    log_success "Dependency analysis report generated: $report_file"
}

# Main analysis function
analyze_dependencies() {
    local services=("$@")
    local output_dir="${OUTPUT_DIR}"
    local format="${FORMAT:-table}"
    
    if [[ ${#services[@]} -eq 0 ]]; then
        log_info "No services specified, analyzing all services"
        
        local all_services
        all_services=$("$SSH_HELPER" exec "find $DOCKER_BASE_PATH -maxdepth 1 -type d -name '[!.]*' | sort" 2>/dev/null) || {
            log_error "Failed to list services"
            return 1
        }
        
        while IFS= read -r service_path; do
            services+=($(basename "$service_path"))
        done <<< "$all_services"
    fi
    
    log_info "Analyzing dependencies for ${#services[@]} services"
    
    # Initialize output directory
    init_output_dir "$output_dir"
    
    local successful=0
    local failed=0
    
    # Analyze each service
    for service in "${services[@]}"; do
        log_info "Processing service: $service ($(($successful + $failed + 1))/${#services[@]})"
        
        if analyze_service_dependencies "$service" "$output_dir"; then
            successful=$((successful + 1))
            log_success "✅ $service"
        else
            failed=$((failed + 1))
            log_error "❌ $service"
        fi
    done
    
    # Build dependency graph
    build_dependency_graph "$output_dir" "$format"
    
    # Detect circular dependencies
    detect_circular_dependencies "$output_dir"
    
    # Generate summary report
    generate_dependency_report "$output_dir"
    
    # Final summary
    log_info "Dependency analysis completed"
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
    local tree_mode=false
    local reverse_deps=false
    local circular_check=false
    local network_analysis=false
    local volume_analysis=false
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
                export FORMAT="$format"
                shift 2
                ;;
            -l|--list)
                list_only=true
                shift
                ;;
            -t|--tree)
                tree_mode=true
                shift
                ;;
            -r|--reverse)
                reverse_deps=true
                shift
                ;;
            -c|--circular)
                circular_check=true
                shift
                ;;
            -n|--network)
                network_analysis=true
                shift
                ;;
            -v|--volumes)
                volume_analysis=true
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
    
    # Validate format
    case "$format" in
        table|json|graph|mermaid|dot)
            ;;
        *)
            log_error "Invalid format: $format. Supported: table, json, graph, mermaid, dot"
            exit 1
            ;;
    esac
    
    # Check SSH connection
    if ! check_ssh_connection; then
        exit 1
    fi
    
    # Handle special modes
    if [[ "$circular_check" == "true" ]]; then
        # Initialize and analyze for circular dependencies only
        init_output_dir "$OUTPUT_DIR"
        analyze_dependencies "${services[@]}"
        exit $?
    fi
    
    if [[ "$tree_mode" == "true" ]]; then
        if [[ ${#services[@]} -eq 0 ]]; then
            log_error "Tree mode requires specific service names"
            exit 1
        fi
        
        init_output_dir "$OUTPUT_DIR"
        
        for service in "${services[@]}"; do
            analyze_service_dependencies "$service" "$OUTPUT_DIR"
            generate_dependency_tree "$service" "$OUTPUT_DIR"
        done
        exit $?
    fi
    
    # Standard analysis
    analyze_dependencies "${services[@]}"
}

# Run main function with all arguments
main "$@"