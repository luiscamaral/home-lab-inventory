#!/bin/bash
# Git Hooks Setup Script for Home Lab Inventory Project
# Configures comprehensive git hooks for local CI validation

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(dirname "$SCRIPT_DIR")"
readonly HOOKS_DIR="$SCRIPT_DIR/hooks"
readonly UTILS_DIR="$SCRIPT_DIR/utils"
readonly CONFIG_DIR="$SCRIPT_DIR/config"
readonly GIT_HOOKS_DIR="$REPO_ROOT/.git/hooks"

# Global state
FORCE_INSTALL=false
BACKUP_EXISTING=true
QUIET_MODE=false

# Helper functions
print_error() {
    echo -e "${RED}❌ ERROR: $1${NC}" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠️  WARNING: $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_step() {
    echo -e "${CYAN}🔄 $1${NC}"
}

print_header() {
    echo -e "${PURPLE}═══════════════════════════════════════════════${NC}"
    echo -e "${PURPLE} $1${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════${NC}"
}

print_highlight() {
    echo -e "${CYAN}🎯 $1${NC}"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Setup comprehensive git hooks for Home Lab Inventory project

OPTIONS:
    -f, --force         Force installation, overwrite existing hooks
    --no-backup         Don't backup existing hooks
    -q, --quiet         Suppress info messages
    -h, --help          Show this help message

FEATURES:
    • Pre-commit hook with YAML validation, secret detection, file checks
    • Commit-msg hook with Conventional Commits validation
    • Pre-push hook with comprehensive validation and testing
    • Integration with existing pre-commit framework and commitlint
    • Cross-platform compatibility (macOS, Linux)
    • Configurable patterns and rules

EXAMPLES:
    $0                  # Standard installation
    $0 --force          # Force overwrite existing hooks
    $0 --quiet          # Silent installation

RETURN CODES:
    0 - Installation successful
    1 - Installation failed
    2 - Invalid arguments or environment
EOF
}

# Check if we're in a git repository
check_git_repository() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        print_error "Not in a git repository"
        print_info "Please run this script from the root of the git repository"
        return 1
    fi

    if [[ ! -d ".git" ]]; then
        print_error "This appears to be a git worktree or submodule"
        print_info "Please run from the main repository root"
        return 1
    fi

    return 0
}

# Check system requirements
check_requirements() {
    print_step "Checking system requirements..."

    local missing_requirements=()

    # Check for required commands
    local required_commands=("git" "python3" "bash")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_requirements+=("$cmd")
        fi
    done

    # Check Python YAML module
    if ! python3 -c "import yaml" 2>/dev/null; then
        print_warning "Python yaml module not found"
        print_info "Install with: pip3 install PyYAML"
        print_info "YAML validation will use basic Python parsing"
    fi

    # Check optional but recommended tools
    local recommended_tools=("shellcheck" "actionlint" "hadolint")
    local missing_recommended=()

    for tool in "${recommended_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_recommended+=("$tool")
        fi
    done

    if [[ ${#missing_requirements[@]} -gt 0 ]]; then
        print_error "Missing required tools: ${missing_requirements[*]}"
        print_info "Please install the missing tools and try again"
        return 1
    fi

    if [[ ${#missing_recommended[@]} -gt 0 ]] && [[ "$QUIET_MODE" == false ]]; then
        print_warning "Missing recommended tools: ${missing_recommended[*]}"
        print_info "Install these for enhanced code quality checks:"

        if command -v brew >/dev/null 2>&1; then
            print_info "  brew install shellcheck actionlint hadolint"
        elif command -v apt-get >/dev/null 2>&1; then
            print_info "  sudo apt-get install shellcheck"
        fi
    fi

    print_success "System requirements check passed"
    return 0
}

# Backup existing hooks
backup_existing_hooks() {
    if [[ "$BACKUP_EXISTING" == false ]]; then
        return 0
    fi

    print_step "Backing up existing git hooks..."

    local backup_dir="$GIT_HOOKS_DIR.backup.$(date +%Y%m%d_%H%M%S)"
    local hooks_backed_up=0

    if [[ -d "$GIT_HOOKS_DIR" ]]; then
        for hook_file in "$GIT_HOOKS_DIR"/*; do
            [[ ! -f "$hook_file" ]] && continue
            [[ "$hook_file" == *.sample ]] && continue

            # Create backup directory if needed
            if [[ $hooks_backed_up -eq 0 ]]; then
                mkdir -p "$backup_dir"
                print_info "Created backup directory: $backup_dir"
            fi

            local hook_name
            hook_name=$(basename "$hook_file")
            cp "$hook_file" "$backup_dir/$hook_name"
            print_info "Backed up: $hook_name"
            ((hooks_backed_up++))
        done
    fi

    if [[ $hooks_backed_up -gt 0 ]]; then
        print_success "Backed up $hooks_backed_up existing hooks"
    else
        print_info "No existing hooks to backup"
    fi

    return 0
}

# Install a single hook
install_hook() {
    local hook_name="$1"
    local source_path="$HOOKS_DIR/$hook_name"
    local target_path="$GIT_HOOKS_DIR/$hook_name"

    if [[ ! -f "$source_path" ]]; then
        print_error "Hook source not found: $source_path"
        return 1
    fi

    # Check if target exists and we're not forcing
    if [[ -f "$target_path" ]] && [[ "$FORCE_INSTALL" == false ]]; then
        print_warning "Hook already exists: $hook_name"
        read -p "Overwrite? [y/N] " -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Skipping $hook_name"
            return 0
        fi
    fi

    # Copy hook and make executable
    cp "$source_path" "$target_path"
    chmod +x "$target_path"

    print_success "Installed: $hook_name"
    return 0
}

# Install all hooks
install_hooks() {
    print_step "Installing git hooks..."

    # Ensure git hooks directory exists
    mkdir -p "$GIT_HOOKS_DIR"

    # Install each hook
    local hooks_to_install=("pre-commit" "commit-msg" "pre-push")
    local installed_hooks=0

    for hook in "${hooks_to_install[@]}"; do
        if install_hook "$hook"; then
            ((installed_hooks++))
        fi
    done

    print_success "Installed $installed_hooks git hooks"
    return 0
}

# Validate hook installation
validate_installation() {
    print_step "Validating hook installation..."

    local validation_errors=0
    local hooks_to_check=("pre-commit" "commit-msg" "pre-push")

    for hook in "${hooks_to_check[@]}"; do
        local hook_path="$GIT_HOOKS_DIR/$hook"

        if [[ ! -f "$hook_path" ]]; then
            print_error "Hook not found: $hook"
            ((validation_errors++))
            continue
        fi

        if [[ ! -x "$hook_path" ]]; then
            print_error "Hook not executable: $hook"
            ((validation_errors++))
            continue
        fi

        # Basic syntax check
        if ! bash -n "$hook_path" 2>/dev/null; then
            print_error "Hook has syntax errors: $hook"
            ((validation_errors++))
            continue
        fi

        print_success "Hook validated: $hook"
    done

    # Check utility scripts
    local utils_to_check=("yaml-validator.py" "secret-detector.sh" "conventional-commits.sh" "file-checks.sh")

    for util in "${utils_to_check[@]}"; do
        local util_path="$UTILS_DIR/$util"

        if [[ ! -f "$util_path" ]]; then
            print_error "Utility not found: $util"
            ((validation_errors++))
            continue
        fi

        if [[ ! -x "$util_path" ]]; then
            print_error "Utility not executable: $util"
            ((validation_errors++))
            continue
        fi

        print_success "Utility validated: $util"
    done

    # Check config files
    local configs_to_check=("secret-patterns.txt" "allowed-file-types.txt")

    for config in "${configs_to_check[@]}"; do
        local config_path="$CONFIG_DIR/$config"

        if [[ ! -f "$config_path" ]]; then
            print_error "Config file not found: $config"
            ((validation_errors++))
            continue
        fi

        print_success "Config validated: $config"
    done

    if [[ $validation_errors -eq 0 ]]; then
        print_success "All components validated successfully"
        return 0
    else
        print_error "$validation_errors validation errors found"
        return 1
    fi
}

# Configure git settings
configure_git_settings() {
    print_step "Configuring git settings..."

    # Set git hooks path (optional - allows using both custom and system hooks)
    if [[ "$FORCE_INSTALL" == true ]] || ! git config --get core.hooksPath >/dev/null 2>&1; then
        git config core.hooksPath .git/hooks
        print_info "Set git hooks path to .git/hooks"
    fi

    print_success "Git configuration updated"
    return 0
}

# Test hook functionality
test_hooks() {
    print_step "Testing hook functionality..."

    # Test pre-commit hook with a simple check
    if [[ -x "$GIT_HOOKS_DIR/pre-commit" ]]; then
        print_info "Testing pre-commit hook..."

        # Create a temporary file for testing
        local temp_file
        temp_file=$(mktemp)
        echo "test: sample test content" > "$temp_file"

        # Stage the file temporarily
        git add "$temp_file"

        # Test the hook (it should pass with our test file)
        if "$GIT_HOOKS_DIR/pre-commit" 2>/dev/null; then
            print_success "Pre-commit hook test passed"
        else
            print_warning "Pre-commit hook test had issues (may be normal)"
        fi

        # Unstage and remove test file
        git reset HEAD "$temp_file" >/dev/null 2>&1
        rm -f "$temp_file"
    fi

    # Test commit-msg hook
    if [[ -x "$GIT_HOOKS_DIR/commit-msg" ]]; then
        print_info "Testing commit-msg hook..."

        local temp_commit_file
        temp_commit_file=$(mktemp)
        echo "test: sample commit message" > "$temp_commit_file"

        if "$GIT_HOOKS_DIR/commit-msg" "$temp_commit_file" >/dev/null 2>&1; then
            print_success "Commit-msg hook test passed"
        else
            print_warning "Commit-msg hook test failed (may need existing commitlint setup)"
        fi

        rm -f "$temp_commit_file"
    fi

    print_success "Hook testing completed"
    return 0
}

# Show usage information
show_usage_info() {
    print_header "Git Hooks Installation Complete"
    echo
    print_highlight "Installed Hooks:"
    echo "  🚀 pre-commit  - YAML validation, secret detection, file checks"
    echo "  📝 commit-msg  - Conventional Commits validation"
    echo "  🔍 pre-push    - Comprehensive validation and testing"
    echo
    print_highlight "Usage:"
    echo "  • Hooks run automatically on git operations"
    echo "  • Skip temporarily: git commit --no-verify"
    echo "  • Skip tests on push: SKIP_TESTS=true git push"
    echo
    print_highlight "Configuration:"
    echo "  • Secret patterns: .githooks/config/secret-patterns.txt"
    echo "  • File types: .githooks/config/allowed-file-types.txt"
    echo
    print_highlight "Integration:"
    echo "  • Works with existing pre-commit framework"
    echo "  • Integrates with commitlint/Husky setup"
    echo "  • Compatible with GitHub Actions workflows"
    echo
    print_highlight "Utilities (can be run manually):"
    echo "  • .githooks/utils/yaml-validator.py --help"
    echo "  • .githooks/utils/secret-detector.sh --help"
    echo "  • .githooks/utils/conventional-commits.sh --help"
    echo "  • .githooks/utils/file-checks.sh --help"
    echo
    print_success "Git hooks are ready to use! 🎉"
}

# Main execution
main() {
    local install_force=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_INSTALL=true
                shift
                ;;
            --no-backup)
                BACKUP_EXISTING=false
                shift
                ;;
            -q|--quiet)
                QUIET_MODE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                usage
                exit 2
                ;;
            *)
                print_error "Unexpected argument: $1"
                usage
                exit 2
                ;;
        esac
    done

    print_header "Git Hooks Setup for Home Lab Inventory"
    echo

    # Pre-flight checks
    if ! check_git_repository; then
        exit 2
    fi

    if ! check_requirements; then
        exit 2
    fi

    echo

    # Installation steps
    if ! backup_existing_hooks; then
        exit 1
    fi

    echo

    if ! install_hooks; then
        exit 1
    fi

    echo

    if ! configure_git_settings; then
        exit 1
    fi

    echo

    if ! validate_installation; then
        exit 1
    fi

    echo

    if ! test_hooks; then
        exit 1
    fi

    echo

    # Show final information
    if [[ "$QUIET_MODE" == false ]]; then
        show_usage_info
    else
        print_success "Git hooks setup completed successfully"
    fi

    exit 0
}

# Run main function
main "$@"
