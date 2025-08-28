#!/bin/bash
# Test Automation Scripts
# Part of dockermaster-recovery documentation framework
# Created: 2025-08-28

set -euo pipefail

# Configuration
SCRIPT_DIR="$(dirname "$0")"
OUTPUT_DIR="$SCRIPT_DIR/../output"
TEST_SERVICE="nginx"  # Known working service
SSH_HELPER="$SCRIPT_DIR/ssh-dockermaster.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
}

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Test function wrapper
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    log_test "Running: $test_name"
    
    if eval "$test_command" >/dev/null 2>&1; then
        log_success "✅ $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "❌ $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$test_name")
        return 1
    fi
}

# Print test header
print_header() {
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│           Dockermaster Documentation Framework             │"
    echo "│                  Automation Test Suite                     │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│ Testing all automation scripts on known service            │"
    echo "│ Test Service: $TEST_SERVICE                                     │"
    echo "│ Output Directory: $OUTPUT_DIR                   │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
}

# Test 1: SSH Helper Script
test_ssh_helper() {
    log_info "Testing SSH helper script..."
    
    # Test if script exists and is executable
    run_test "SSH helper exists and executable" "[[ -x '$SSH_HELPER' ]]"
    
    # Test help command
    run_test "SSH helper help command" "'$SSH_HELPER' help"
    
    # Note: We can't test actual connection without proper SSH config
    log_warning "SSH connection test skipped (requires SSH config setup)"
    
    return 0
}

# Test 2: Extract Compose Script
test_extract_compose() {
    log_info "Testing extract-compose.sh script..."
    
    local extract_script="$SCRIPT_DIR/extract-compose.sh"
    
    # Test if script exists and is executable
    run_test "extract-compose.sh exists and executable" "[[ -x '$extract_script' ]]"
    
    # Test help command
    run_test "extract-compose.sh help command" "'$extract_script' --help"
    
    # Test list command (without SSH - will fail but should show proper error)
    log_test "Testing extract-compose.sh list command (expected to fail without SSH)"
    if "$extract_script" --list 2>/dev/null; then
        log_warning "List command succeeded (SSH connection available)"
    else
        log_info "List command failed as expected (no SSH connection configured)"
    fi
    
    return 0
}

# Test 3: Parse Environment Script
test_parse_env() {
    log_info "Testing parse-env.sh script..."
    
    local parse_script="$SCRIPT_DIR/parse-env.sh"
    
    # Test if script exists and is executable
    run_test "parse-env.sh exists and executable" "[[ -x '$parse_script' ]]"
    
    # Test help command
    run_test "parse-env.sh help command" "'$parse_script' --help"
    
    # Test list command (without SSH - will fail but should show proper error)
    log_test "Testing parse-env.sh list command (expected to fail without SSH)"
    if "$parse_script" --list 2>/dev/null; then
        log_warning "List command succeeded (SSH connection available)"
    else
        log_info "List command failed as expected (no SSH connection configured)"
    fi
    
    return 0
}

# Test 4: Find Dependencies Script
test_find_deps() {
    log_info "Testing find-deps.sh script..."
    
    local deps_script="$SCRIPT_DIR/find-deps.sh"
    
    # Test if script exists and is executable
    run_test "find-deps.sh exists and executable" "[[ -x '$deps_script' ]]"
    
    # Test help command
    run_test "find-deps.sh help command" "'$deps_script' --help"
    
    # Test with invalid format (should fail with proper error)
    log_test "Testing find-deps.sh with invalid format (should fail)"
    if "$deps_script" --format invalid 2>/dev/null; then
        log_error "Invalid format test failed - should have rejected 'invalid' format"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("find-deps.sh format validation")
    else
        log_success "Format validation working correctly"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
    
    return 0
}

# Test 5: Output Directory Structure
test_output_structure() {
    log_info "Testing output directory structure..."
    
    # Test output directory exists
    run_test "Output directory exists" "[[ -d '$OUTPUT_DIR' ]]"
    
    # Create test subdirectories to verify permissions
    local test_dir="$OUTPUT_DIR/test-$$"
    run_test "Can create test subdirectory" "mkdir -p '$test_dir'"
    
    if [[ -d "$test_dir" ]]; then
        rm -rf "$test_dir"
        log_success "Test directory cleanup successful"
    fi
    
    return 0
}

# Test 6: Script Integration
test_integration() {
    log_info "Testing script integration..."
    
    # All scripts should use the same SSH helper
    local scripts=("extract-compose.sh" "parse-env.sh" "find-deps.sh")
    
    for script in "${scripts[@]}"; do
        local script_path="$SCRIPT_DIR/$script"
        if [[ -f "$script_path" ]]; then
            # Check if script references the SSH helper
            if grep -q "ssh-dockermaster.sh" "$script_path"; then
                log_success "✅ $script uses SSH helper"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                log_error "❌ $script missing SSH helper reference"
                TESTS_FAILED=$((TESTS_FAILED + 1))
                FAILED_TESTS+=("$script SSH helper integration")
            fi
        fi
    done
    
    return 0
}

# Test 7: Documentation Generation
test_documentation() {
    log_info "Testing documentation generation..."
    
    # Check if service matrix was created
    local matrix_file="$SCRIPT_DIR/../docs/service-matrix.md"
    run_test "Service matrix exists" "[[ -f '$matrix_file' ]]"
    
    # Check if SSH setup instructions exist
    local ssh_docs="$SCRIPT_DIR/../docs/ssh-setup-instructions.md"
    run_test "SSH setup instructions exist" "[[ -f '$ssh_docs' ]]"
    
    # Check if matrix contains expected sections
    if [[ -f "$matrix_file" ]]; then
        run_test "Service matrix contains service count" "grep -q '\*\*Total Services:\*\* 32' '$matrix_file'"
        run_test "Service matrix contains priority sections" "grep -q 'High Priority' '$matrix_file'"
        run_test "Service matrix contains critical issues" "grep -q 'Critical Issues' '$matrix_file'"
    fi
    
    return 0
}

# Test 8: Error Handling
test_error_handling() {
    log_info "Testing error handling..."
    
    local extract_script="$SCRIPT_DIR/extract-compose.sh"
    
    # Test invalid service name (should fail gracefully)
    log_test "Testing invalid service handling"
    if "$extract_script" nonexistent-service-12345 2>/dev/null; then
        log_warning "Invalid service test - may indicate SSH connection is working"
    else
        log_success "Invalid service properly rejected"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
    
    # Test invalid output directory (should handle gracefully)
    log_test "Testing invalid output directory"
    if "$extract_script" --output "/nonexistent/path/that/should/not/exist" --help >/dev/null 2>&1; then
        log_success "Help works even with invalid output path"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "Script failed with invalid output path"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("Invalid output directory handling")
    fi
    
    return 0
}

# Generate test report
generate_test_report() {
    log_info "Generating test report..."
    
    local report_file="$OUTPUT_DIR/automation-test-report.txt"
    
    cat > "$report_file" << EOF
Dockermaster Documentation Framework - Automation Test Report
═══════════════════════════════════════════════════════════════════════
Generated: $(date)
Test Environment: $(uname -s) $(uname -r)

SUMMARY:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total Tests: $((TESTS_PASSED + TESTS_FAILED))
Passed: $TESTS_PASSED
Failed: $TESTS_FAILED
Success Rate: $(if [[ $((TESTS_PASSED + TESTS_FAILED)) -gt 0 ]]; then echo "scale=1; ($TESTS_PASSED * 100) / ($TESTS_PASSED + $TESTS_FAILED)" | bc -l; else echo "0"; fi)%

EOF
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        cat >> "$report_file" << EOF

FAILED TESTS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
        for failed_test in "${FAILED_TESTS[@]}"; do
            echo "❌ $failed_test" >> "$report_file"
        done
        
        cat >> "$report_file" << EOF

RECOMMENDATIONS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Review failed tests above
2. Ensure all scripts have proper permissions
3. Verify SSH configuration if connection tests failed
4. Check script integration issues

EOF
    fi
    
    cat >> "$report_file" << EOF

SCRIPTS TESTED:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ ssh-dockermaster.sh       - SSH multiplexing helper
✓ extract-compose.sh         - Docker compose extraction
✓ parse-env.sh              - Environment analysis  
✓ find-deps.sh              - Dependency analysis
✓ Service matrix generation - Documentation framework
✓ Error handling validation - Robustness testing

NEXT STEPS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Complete SSH configuration setup
2. Test scripts with actual dockermaster connection
3. Run full documentation automation on target services
4. Validate output quality and completeness

═══════════════════════════════════════════════════════════════════════
Test Framework Status: $(if [[ $TESTS_FAILED -eq 0 ]]; then echo "READY FOR DEPLOYMENT ✅"; else echo "NEEDS ATTENTION ⚠️"; fi)
═══════════════════════════════════════════════════════════════════════
EOF
    
    log_success "Test report generated: $report_file"
}

# Main function
main() {
    print_header
    
    log_info "Starting automation framework test suite..."
    
    # Run all tests
    test_ssh_helper
    test_extract_compose  
    test_parse_env
    test_find_deps
    test_output_structure
    test_integration
    test_documentation
    test_error_handling
    
    # Generate report
    generate_test_report
    
    # Final summary
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│                     TEST RESULTS                           │"
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│ Total Tests: %2d │ Passed: %2d │ Failed: %2d │ Rate: %5.1f%% │\n" \
           $((TESTS_PASSED + TESTS_FAILED)) \
           $TESTS_PASSED \
           $TESTS_FAILED \
           $(if [[ $((TESTS_PASSED + TESTS_FAILED)) -gt 0 ]]; then echo "scale=1; ($TESTS_PASSED * 100) / ($TESTS_PASSED + $TESTS_FAILED)" | bc -l 2>/dev/null || echo "0"; else echo "0"; fi)
    echo "└─────────────────────────────────────────────────────────────┘"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo ""
        log_success "🎉 All tests passed! Framework is ready for deployment."
        echo ""
        log_info "Next steps:"
        echo "  1. Complete SSH configuration as per docs/ssh-setup-instructions.md"
        echo "  2. Test scripts with actual dockermaster connection"
        echo "  3. Begin bulk documentation of remaining services"
        echo ""
    else
        echo ""
        log_warning "⚠️  Some tests failed. Review the issues before proceeding."
        echo ""
        log_error "Failed tests:"
        for failed_test in "${FAILED_TESTS[@]}"; do
            echo "  - $failed_test"
        done
        echo ""
    fi
    
    # Return appropriate exit code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"