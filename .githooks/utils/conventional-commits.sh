#!/bin/bash
#
# Conventional Commits Validator - Git Hook Utility
# Validates commit messages according to the Conventional Commits specification.
#
# Usage:
#   conventional-commits.sh [options] [commit-message]
#   conventional-commits.sh --help
#
# Options:
#   -h, --help          Show this help message and exit
#   -q, --quiet         Suppress informational output
#   -v, --verbose       Show detailed validation information
#   -f, --file FILE     Read commit message from file
#   --no-color          Disable colored output
#   --allow-fixup       Allow fixup and squash commits
#   --strict            Enable strict validation (require scope)
#
# Exit codes:
#   0 - Commit message is valid
#   1 - Commit message is invalid
#   2 - Script usage error
#
# Conventional Commits Format:
#   <type>[optional scope]: <description>
#
#   [optional body]
#
#   [optional footer(s)]
#

set -euo pipefail

# Default configuration
VERBOSE=false
QUIET=false
USE_COLOR=true
ALLOW_FIXUP=false
STRICT_MODE=false
COMMIT_FILE=""
COMMIT_MESSAGE=""

# Color definitions
RED='\033[91m'
GREEN='\033[92m'
YELLOW='\033[93m'
BLUE='\033[94m'
MAGENTA='\033[95m'
CYAN='\033[96m'
WHITE='\033[97m'
BOLD='\033[1m'
UNDERLINE='\033[4m'
END='\033[0m'

# Valid commit types according to Angular convention and common extensions
VALID_TYPES=(
    "feat"      # New feature
    "fix"       # Bug fix
    "docs"      # Documentation only changes
    "style"     # Changes that do not affect the meaning of the code
    "refactor"  # Code change that neither fixes a bug nor adds a feature
    "perf"      # Performance improvement
    "test"      # Adding missing tests or correcting existing tests
    "build"     # Changes that affect the build system or external dependencies
    "ci"        # Changes to CI configuration files and scripts
    "chore"     # Other changes that don't modify src or test files
    "revert"    # Reverts a previous commit
    "wip"       # Work in progress (if allowed)
    "hotfix"    # Critical fixes
    "release"   # Release commits
    "merge"     # Merge commits
)

# Breaking change indicators
BREAKING_CHANGE_INDICATORS=(
    "!"
    "BREAKING CHANGE:"
    "BREAKING-CHANGE:"
)

# Function to disable colors
disable_colors() {
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    MAGENTA=''
    CYAN=''
    WHITE=''
    BOLD=''
    UNDERLINE=''
    END=''
}

# Logging functions
log_info() {
    if [[ "$QUIET" != true ]]; then
        echo -e "${CYAN}ℹ${END}  $*"
    fi
}

log_success() {
    if [[ "$QUIET" != true ]]; then
        echo -e "${GREEN}✓${END}  $*"
    fi
}

log_warning() {
    echo -e "${YELLOW}⚠${END}  $*" >&2
}

log_error() {
    echo -e "${RED}✗${END}  $*" >&2
}

log_detail() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "  ${BLUE}→${END} $*"
    fi
}

# Function to show help
show_help() {
    cat << EOF
Conventional Commits Validator - Git Hook Utility

USAGE:
    conventional-commits.sh [OPTIONS] [commit-message]
    conventional-commits.sh -f <file>

OPTIONS:
    -h, --help          Show this help message and exit
    -q, --quiet         Suppress informational output
    -v, --verbose       Show detailed validation information
    -f, --file FILE     Read commit message from file
    --no-color          Disable colored output
    --allow-fixup       Allow fixup and squash commits
    --strict            Enable strict validation (require scope)

COMMIT MESSAGE FORMAT:
    <type>[optional scope]: <description>

    [optional body]

    [optional footer(s)]

VALID TYPES:
    feat      - New feature
    fix       - Bug fix
    docs      - Documentation only changes
    style     - Code style changes (formatting, etc.)
    refactor  - Code refactoring
    perf      - Performance improvement
    test      - Adding or fixing tests
    build     - Build system or external dependencies
    ci        - CI configuration changes
    chore     - Other changes
    revert    - Reverts a previous commit

EXAMPLES:
    feat: add user authentication
    fix(auth): resolve login timeout issue
    docs: update API documentation
    feat(api)!: change user endpoint structure

    # Breaking change with body
    feat: add new payment system

    BREAKING CHANGE: payment API has changed

BREAKING CHANGES:
    - Add '!' after type/scope: feat!: or feat(scope)!:
    - Add footer: BREAKING CHANGE: description

EXIT CODES:
    0 - Commit message is valid
    1 - Commit message is invalid
    2 - Script usage error
EOF
}

# Function to check if type is valid
is_valid_type() {
    local type="$1"
    for valid_type in "${VALID_TYPES[@]}"; do
        if [[ "$type" == "$valid_type" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to validate commit message format
validate_commit_message() {
    local message="$1"
    local valid=true

    # Skip empty messages
    if [[ -z "$message" ]]; then
        log_error "Commit message is empty"
        return 1
    fi

    # Get the first line (subject)
    local subject
    subject=$(echo "$message" | head -n1)

    log_info "Validating commit message: ${YELLOW}$subject${END}"

    # Check for fixup/squash commits if allowed
    if [[ "$ALLOW_FIXUP" == true ]]; then
        if echo "$subject" | grep -qE '^(fixup|squash)!'; then
            log_success "Valid fixup/squash commit"
            return 0
        fi
    fi

    # Check for merge commits (allow them)
    if echo "$subject" | grep -qE '^Merge'; then
        log_success "Valid merge commit"
        return 0
    fi

    # Check for revert commits
    if [[ "$subject" =~ ^Revert ]]; then
        log_success "Valid revert commit"
        return 0
    fi

    # Basic format validation: <type>[scope]: <description>
    if ! echo "$subject" | grep -qE '^[a-z]+(\([^)]+\))?!?:[[:space:]]+.+'; then
        log_error "Invalid commit message format"
        log_detail "Expected format: <type>[optional scope]: <description>"
        log_detail "Example: feat(auth): add user login functionality"
        return 1
    fi

    # Extract components using a different method since we simplified the regex
    local type
    local scope=""
    local breaking=""

    # Extract type
    type=$(echo "$subject" | sed -n 's/^\([a-z]*\).*/\1/p')

    # Extract scope if present
    if echo "$subject" | grep -q '([^)]*)'; then
        scope=$(echo "$subject" | sed -n 's/.*(\([^)]*\)).*/\1/p')
    fi

    # Check for breaking change indicator
    if echo "$subject" | grep -q '!'; then
        breaking="!"
    fi

    # Get description (everything after the colon and space)
    local description
    description=$(echo "$subject" | sed -n 's/^[a-z]*(\?[^)]*)\?!*:[[:space:]]*//p')

    log_detail "Type: ${MAGENTA}$type${END}"
    [[ -n "$scope" ]] && log_detail "Scope: ${MAGENTA}$scope${END}"
    [[ "$breaking" == "!" ]] && log_detail "Breaking change: ${RED}YES${END}"
    log_detail "Description: ${MAGENTA}$description${END}"

    # Validate type
    if ! is_valid_type "$type"; then
        log_error "Invalid commit type: $type"
        log_detail "Valid types: ${VALID_TYPES[*]}"
        valid=false
    fi

    # Strict mode: require scope
    if [[ "$STRICT_MODE" == true && -z "$scope" ]]; then
        log_error "Scope is required in strict mode"
        log_detail "Example: feat(auth): add login functionality"
        valid=false
    fi

    # Validate description
    if [[ -z "$description" ]]; then
        log_error "Description is required"
        valid=false
    elif [[ ${#description} -lt 3 ]]; then
        log_error "Description is too short (minimum 3 characters)"
        valid=false
    elif [[ ${#description} -gt 72 ]]; then
        log_warning "Description is long (${#description} characters, recommended max 72)"
        log_detail "Consider moving details to the commit body"
    fi

    # Check description format
    if [[ "$description" =~ ^[A-Z] ]]; then
        log_warning "Description should start with lowercase letter"
        log_detail "Example: 'add feature' not 'Add feature'"
    fi

    if [[ "$description" =~ \.$ ]]; then
        log_warning "Description should not end with a period"
    fi

    # Validate scope format if present
    if [[ -n "$scope" ]]; then
        if ! echo "$scope" | grep -qE '^[a-z0-9-]+$'; then
            log_error "Scope should contain only lowercase letters, numbers, and hyphens"
            valid=false
        elif [[ ${#scope} -gt 20 ]]; then
            log_warning "Scope is long (${#scope} characters, recommended max 20)"
        fi
    fi

    # Check for breaking changes in body/footer
    local has_breaking_footer=false
    if echo "$message" | grep -qE "^(BREAKING CHANGE|BREAKING-CHANGE):"; then
        has_breaking_footer=true
        log_detail "Breaking change footer detected"
    fi

    # Validate breaking change consistency
    if [[ "$breaking" == "!" && "$has_breaking_footer" == false ]]; then
        log_warning "Breaking change indicator (!) found but no BREAKING CHANGE footer"
        log_detail "Consider adding: BREAKING CHANGE: describe the breaking change"
    elif [[ "$breaking" != "!" && "$has_breaking_footer" == true ]]; then
        log_warning "BREAKING CHANGE footer found but no breaking change indicator (!)"
        log_detail "Consider adding ! after type: $type!: or ${type}(${scope})!:"
    fi

    # Check body and footer format (if present)
    local lines
    mapfile -t lines <<< "$message"

    if [[ ${#lines[@]} -gt 1 ]]; then
        # Check for blank line after subject
        if [[ -n "${lines[1]}" ]]; then
            log_error "Missing blank line after subject"
            log_detail "Add a blank line between subject and body"
            valid=false
        fi

        # Check body line lengths
        for ((i=2; i<${#lines[@]}; i++)); do
            local line="${lines[i]}"
            if [[ ${#line} -gt 100 ]]; then
                log_warning "Line $((i+1)) is long (${#line} characters, recommended max 100)"
            fi
        done
    fi

    # Additional validations
    if echo "$subject" | grep -qE '^[[:space:]]'; then
        log_error "Subject line should not start with whitespace"
        valid=false
    fi

    if [[ "$subject" =~ [[:space:]]$ ]]; then
        log_error "Subject line should not end with whitespace"
        valid=false
    fi

    if [[ "$valid" == true ]]; then
        log_success "Commit message follows Conventional Commits specification"
        if [[ "$VERBOSE" == true ]]; then
            echo ""
            echo -e "${GREEN}${BOLD}✓ Valid Commit Message${END}"
            echo -e "${BLUE}Format:${END} $type${scope:+($scope)}${breaking}${breaking:+ }${description}"
            [[ "$has_breaking_footer" == true ]] && echo -e "${RED}Breaking Change:${END} YES"
        fi
        return 0
    else
        log_error "Commit message validation failed"
        echo ""
        echo -e "${YELLOW}${BOLD}💡 Conventional Commits Help:${END}"
        echo -e "${BLUE}Format:${END} <type>[optional scope]: <description>"
        echo ""
        echo -e "${BLUE}Examples:${END}"
        echo "  feat: add user authentication"
        echo "  fix(auth): resolve login timeout"
        echo "  docs: update API documentation"
        echo "  feat(api)!: change user endpoint"
        echo ""
        return 1
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -f|--file)
                if [[ -z "${2:-}" ]]; then
                    log_error "Commit message file path required for --file option"
                    exit 2
                fi
                COMMIT_FILE="$2"
                shift 2
                ;;
            --no-color)
                USE_COLOR=false
                shift
                ;;
            --allow-fixup)
                ALLOW_FIXUP=true
                shift
                ;;
            --strict)
                STRICT_MODE=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                show_help
                exit 2
                ;;
            *)
                if [[ -n "$COMMIT_MESSAGE" ]]; then
                    log_error "Only one commit message can be specified"
                    exit 2
                fi
                COMMIT_MESSAGE="$1"
                shift
                ;;
        esac
    done
}

# Main function
main() {
    # Parse arguments
    parse_args "$@"

    # Set up colors
    if [[ "$USE_COLOR" == false ]] || [[ ! -t 1 ]]; then
        disable_colors
    fi

    # Get commit message
    local message=""

    if [[ -n "$COMMIT_FILE" ]]; then
        if [[ ! -f "$COMMIT_FILE" ]]; then
            log_error "Commit message file not found: $COMMIT_FILE"
            exit 2
        fi
        message=$(cat "$COMMIT_FILE")
        log_detail "Reading commit message from file: $COMMIT_FILE"
    elif [[ -n "$COMMIT_MESSAGE" ]]; then
        message="$COMMIT_MESSAGE"
    else
        # Try to read from stdin if no message provided
        if [[ ! -t 0 ]]; then
            message=$(cat)
        else
            log_error "No commit message provided"
            show_help
            exit 2
        fi
    fi

    # Validate the commit message
    if validate_commit_message "$message"; then
        exit 0
    else
        exit 1
    fi
}

# Run main function with all arguments
main "$@"
