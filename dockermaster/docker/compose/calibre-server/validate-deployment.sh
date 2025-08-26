#!/bin/bash

# =============================================================================
# Calibre to Portainer Migration - Deployment Validation Script
# Agent E: Validation Specialist
# Date: $(date +%Y-%m-%d)
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.portainer.yml"
ENV_FILE="$SCRIPT_DIR/.env"
ENV_EXAMPLE="$SCRIPT_DIR/.env.example"
RESULTS_FILE="$SCRIPT_DIR/test-results.json"
ISSUES_FILE="$SCRIPT_DIR/validation-issues.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
TEST_RESULTS_FILE="/tmp/test_results_$"

# Required ports for Calibre services
REQUIRED_PORTS=(58080 58181 58081 58090 58083)

# Required volume paths
REQUIRED_VOLUMES=(
  "/nfs/calibre/Library"
  "/nfs/calibre/config"
  "/nfs/calibre/upload"
  "/nfs/calibre/plugins"
  "/nfs/calibre/calibre-web/config"
  "/nfs/calibre/calibre-web/Library"
)

# Required environment variables
REQUIRED_ENV_VARS=(
  "CALIBRE_PASSWORD"
  "PUID"
  "PGID"
  "TZ"
)

# =============================================================================
# Utility Functions
# =============================================================================

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[PASS]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[FAIL]${NC} $1"
}

record_test() {
  local test_name="$1"
  local result="$2"
  local message="$3"

  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  echo "${test_name}:${result}" >> "$TEST_RESULTS_FILE"

  if [[ "$result" == "pass" ]]; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
    log_success "$test_name: $message"
  else
    FAILED_TESTS=$((FAILED_TESTS + 1))
    log_error "$test_name: $message"
    echo "- $test_name: $message" >> "$ISSUES_FILE"
  fi
}

# =============================================================================
# Test Functions
# =============================================================================

test_docker_compose_syntax() {
  log_info "Testing Docker Compose syntax validation..."

  if [[ ! -f "$COMPOSE_FILE" ]]; then
    record_test "compose_file_exists" "fail" "docker-compose.portainer.yml not found"
    return 1
  fi

  if docker compose -f "$COMPOSE_FILE" config > /dev/null 2>&1; then
    record_test "compose_syntax" "pass" "Docker Compose syntax is valid"
  else
    local error_output=$(docker compose -f "$COMPOSE_FILE" config 2>&1 || true)
    record_test "compose_syntax" "fail" "Docker Compose syntax error: $error_output"
  fi
}

test_port_availability() {
  log_info "Testing port availability..."

  local ports_available=true
  local busy_ports=()

  for port in "${REQUIRED_PORTS[@]}"; do
    if command -v netstat > /dev/null 2>&1; then
      if netstat -an 2> /dev/null | grep -q ":$port "; then
        busy_ports+=("$port")
        ports_available=false
      fi
    elif command -v ss > /dev/null 2>&1; then
      if ss -ln 2> /dev/null | grep -q ":$port "; then
        busy_ports+=("$port")
        ports_available=false
      fi
    else
      record_test "port_check_tools" "fail" "Neither netstat nor ss available for port checking"
      return 1
    fi
  done

  if [[ "$ports_available" == true ]]; then
    record_test "port_availability" "pass" "All required ports (${REQUIRED_PORTS[*]}) are available"
  else
    record_test "port_availability" "fail" "Ports already in use: ${busy_ports[*]}"
  fi
}

test_volume_paths() {
  log_info "Testing volume path accessibility..."

  local volumes_ok=true
  local missing_volumes=()

  for volume_path in "${REQUIRED_VOLUMES[@]}"; do
    if [[ ! -d "$volume_path" ]]; then
      missing_volumes+=("$volume_path")
      volumes_ok=false
    fi
  done

  if [[ "$volumes_ok" == true ]]; then
    record_test "volume_paths" "pass" "All required volume paths exist"
  else
    record_test "volume_paths" "fail" "Missing volume paths: ${missing_volumes[*]}"
  fi
}

test_environment_variables() {
  log_info "Testing environment variables..."

  # Check if .env file exists
  if [[ ! -f "$ENV_FILE" ]]; then
    if [[ -f "$ENV_EXAMPLE" ]]; then
      record_test "env_file_exists" "fail" ".env file missing, but .env.example found - copy and configure it"
    else
      record_test "env_file_exists" "fail" "Neither .env nor .env.example found"
    fi
    return 1
  fi

  record_test "env_file_exists" "pass" ".env file found"

  # Source the .env file safely
  local env_vars_ok=true
  local missing_vars=()

  # Read .env file and check required variables
  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue

    # Export the variable
    export "$line" 2> /dev/null || true
  done < "$ENV_FILE"

  for var in "${REQUIRED_ENV_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      missing_vars+=("$var")
      env_vars_ok=false
    fi
  done

  if [[ "$env_vars_ok" == true ]]; then
    record_test "env_variables" "pass" "All required environment variables are set"
  else
    record_test "env_variables" "fail" "Missing environment variables: ${missing_vars[*]}"
  fi
}

test_docker_images() {
  log_info "Testing Docker image availability..."

  local images_ok=true
  local missing_images=()

  # Extract images from compose file
  local images=(
    "ghcr.io/luiscamaral/calibre-server:latest"
    "lscr.io/linuxserver/calibre-web:latest"
  )

  for image in "${images[@]}"; do
    if ! docker image inspect "$image" > /dev/null 2>&1; then
      # Try to pull the image
      if ! docker pull "$image" > /dev/null 2>&1; then
        missing_images+=("$image")
        images_ok=false
      fi
    fi
  done

  if [[ "$images_ok" == true ]]; then
    record_test "docker_images" "pass" "All required Docker images are available"
  else
    record_test "docker_images" "fail" "Cannot pull images: ${missing_images[*]}"
  fi
}

test_network_configuration() {
  log_info "Testing network configuration..."

  # Check if docker daemon is running
  if ! docker info > /dev/null 2>&1; then
    record_test "docker_daemon" "fail" "Docker daemon is not running or accessible"
    return 1
  fi

  record_test "docker_daemon" "pass" "Docker daemon is running and accessible"

  # Check if we can create networks (test default bridge)
  if docker network ls > /dev/null 2>&1; then
    record_test "network_access" "pass" "Docker network access is functional"
  else
    record_test "network_access" "fail" "Cannot access Docker networks"
  fi
}

test_portainer_compatibility() {
  log_info "Testing Portainer stack compatibility..."

  # Check for Portainer-specific labels
  local portainer_labels_found=false

  if grep -q "portainer\." "$COMPOSE_FILE"; then
    portainer_labels_found=true
  fi

  # Check for proper stack naming
  local has_stack_name=false
  if grep -q "^name:" "$COMPOSE_FILE"; then
    has_stack_name=true
  fi

  # Check for restart policies (Portainer recommendation)
  local has_restart_policy=false
  if grep -q "restart:" "$COMPOSE_FILE"; then
    has_restart_policy=true
  fi

  local compatibility_issues=()

  if [[ "$portainer_labels_found" != true ]]; then
    compatibility_issues+=("No Portainer labels found")
  fi

  if [[ "$has_stack_name" != true ]]; then
    compatibility_issues+=("No stack name defined")
  fi

  if [[ "$has_restart_policy" != true ]]; then
    compatibility_issues+=("No restart policy defined")
  fi

  if [[ ${#compatibility_issues[@]} -eq 0 ]]; then
    record_test "portainer_compatibility" "pass" "Docker Compose file is Portainer-compatible"
  else
    record_test "portainer_compatibility" "warn" "Potential compatibility issues: ${compatibility_issues[*]}"
  fi
}

test_security_configuration() {
  log_info "Testing security configuration..."

  local security_issues=()

  # Check for password configuration
  if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
    if [[ -z "${CALIBRE_PASSWORD:-}" ]]; then
      security_issues+=("CALIBRE_PASSWORD not set")
    elif [[ "${CALIBRE_PASSWORD}" == "your_secure_password_here" ]]; then
      security_issues+=("CALIBRE_PASSWORD still using default/example value")
    fi
  fi

  # Check for secure user configuration
  if grep -q "seccomp:unconfined" "$COMPOSE_FILE"; then
    security_issues+=("seccomp disabled (security risk but may be required)")
  fi

  # Check for proper user mapping
  if ! grep -q "PUID" "$COMPOSE_FILE"; then
    security_issues+=("No user ID mapping configured")
  fi

  if [[ ${#security_issues[@]} -eq 0 ]]; then
    record_test "security_config" "pass" "Security configuration appears proper"
  else
    record_test "security_config" "warn" "Security considerations: ${security_issues[*]}"
  fi
}

test_healthchecks() {
  log_info "Testing health check configuration..."

  local healthcheck_count=$(grep -c "healthcheck:" "$COMPOSE_FILE" || echo "0")

  if [[ "$healthcheck_count" -gt 0 ]]; then
    record_test "healthchecks" "pass" "Health checks configured for services"
  else
    record_test "healthchecks" "warn" "No health checks configured"
  fi
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
  echo "============================================================================="
  echo "Calibre Portainer Deployment Validation"
  echo "Agent E: Validation Specialist"
  echo "Date: $(date)"
  echo "============================================================================="
  echo

  # Initialize issues file
  echo "# Calibre Portainer Migration - Validation Issues" > "$ISSUES_FILE"
  echo "Generated on: $(date)" >> "$ISSUES_FILE"
  echo >> "$ISSUES_FILE"

  # Run all validation tests
  test_docker_compose_syntax
  test_port_availability
  test_volume_paths
  test_environment_variables
  test_docker_images
  test_network_configuration
  test_portainer_compatibility
  test_security_configuration
  test_healthchecks

  echo
  echo "============================================================================="
  echo "VALIDATION SUMMARY"
  echo "============================================================================="
  echo "Total Tests: $TOTAL_TESTS"
  echo "Passed: $PASSED_TESTS"
  echo "Failed: $FAILED_TESTS"
  echo

  # Determine overall deployment readiness
  local deployment_ready=true
  local blocking_issues=false

  # Check for critical failures
  if [[ -f "$TEST_RESULTS_FILE" ]]; then
    for critical_test in "compose_syntax" "env_file_exists" "docker_daemon"; do
      if grep -q "${critical_test}:fail" "$TEST_RESULTS_FILE"; then
        blocking_issues=true
        deployment_ready=false
      fi
    done
  fi

  # Generate JSON results
  generate_json_results "$deployment_ready"

  # Final status
  if [[ "$deployment_ready" == true ]]; then
    if [[ "$FAILED_TESTS" -eq 0 ]]; then
      log_success "✅ DEPLOYMENT READY - All tests passed"
    else
      log_warning "⚠️  DEPLOYMENT READY - Some warnings present, review recommended"
    fi
    echo "Status: SUCCESS"
    echo "Deployment Readiness: YES"
  else
    log_error "❌ DEPLOYMENT NOT READY - Critical issues found"
    echo "Status: FAIL"
    echo "Deployment Readiness: NO"
    echo "Review $ISSUES_FILE for details"
  fi

  echo
  echo "Results saved to: $RESULTS_FILE"
  echo "Issues documented in: $ISSUES_FILE"

  # Return appropriate exit code
  if [[ "$deployment_ready" == true ]]; then
    exit 0
  else
    exit 1
  fi
}

generate_json_results() {
  local ready="$1"

  cat > "$RESULTS_FILE" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "migration_agent": "Agent E - Validation Specialist",
  "tests": {
EOF

  local first=true
  if [[ -f "$TEST_RESULTS_FILE" ]]; then
    while IFS=':' read -r test_name result; do
      if [[ "$first" == true ]]; then
        first=false
      else
        echo "," >> "$RESULTS_FILE"
      fi
      echo "    \"$test_name\": \"$result\"" >> "$RESULTS_FILE"
    done < "$TEST_RESULTS_FILE"
  fi

  cat >> "$RESULTS_FILE" << EOF

  },
  "summary": {
    "total_tests": $TOTAL_TESTS,
    "passed_tests": $PASSED_TESTS,
    "failed_tests": $FAILED_TESTS,
    "success_rate": "$((PASSED_TESTS * 100 / TOTAL_TESTS))%"
  },
  "ready_for_portainer": $ready,
  "deployment_readiness": "$(if [[ "$ready" == true ]]; then echo "YES"; else echo "NO"; fi)",
  "blocking_issues": $(if [[ "$FAILED_TESTS" -gt 0 ]]; then echo "true"; else echo "false"; fi),
  "notes": "Validation completed by Agent E. Review validation-issues.md for any concerns.",
  "next_steps": [
    "$(if [[ "$ready" == true ]]; then echo "Proceed with Portainer stack deployment"; else echo "Resolve blocking issues before deployment"; fi)",
    "Monitor services after deployment",
    "Verify data integrity post-migration"
  ]
}
EOF
}

# Cleanup function
cleanup() {
  [[ -f "$TEST_RESULTS_FILE" ]] && rm -f "$TEST_RESULTS_FILE"
}

# Set trap for cleanup
trap cleanup EXIT

# Execute main function
main "$@"
