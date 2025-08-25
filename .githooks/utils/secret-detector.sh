#!/bin/bash
#
# Secret Detector - Git Hook Utility
# Detects potential secrets and sensitive information in files using configurable patterns.
#
# Usage:
#   secret-detector.sh [options] <file1> [file2] ...
#   secret-detector.sh --help
#
# Options:
#   -h, --help          Show this help message and exit
#   -q, --quiet         Suppress informational output
#   -v, --verbose       Show detailed detection information
#   -c, --config FILE   Use custom configuration file
#   --no-color          Disable colored output
#   --staged-only       Only check staged files (git hook mode)
#
# Exit codes:
#   0 - No secrets detected
#   1 - Secrets detected
#   2 - Script usage error
#
# Configuration:
#   The script uses patterns from ~/.githooks-config.yml or a custom config file
#   to define what constitutes a secret. Patterns can be regular expressions.
#

set -euo pipefail

# Default configuration
DEFAULT_CONFIG_FILE="$HOME/.githooks-config.yml"
CONFIG_FILE=""
VERBOSE=false
QUIET=false
STAGED_ONLY=false
USE_COLOR=true
FOUND_SECRETS=false

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

# Default secret patterns (if no config file exists)
DEFAULT_PATTERNS=(
    # API Keys
    "api[_-]?key['\"]?\s*[:=]\s*['\"]?[A-Za-z0-9_-]{20,}['\"]?"
    "secret[_-]?key['\"]?\s*[:=]\s*['\"]?[A-Za-z0-9_-]{20,}['\"]?"
    "access[_-]?token['\"]?\s*[:=]\s*['\"]?[A-Za-z0-9_-]{20,}['\"]?"

    # AWS
    "AKIA[0-9A-Z]{16}"
    "aws[_-]?access[_-]?key[_-]?id['\"]?\s*[:=]\s*['\"]?[A-Z0-9]{20}['\"]?"
    "aws[_-]?secret[_-]?access[_-]?key['\"]?\s*[:=]\s*['\"]?[A-Za-z0-9/+=]{40}['\"]?"

    # Google API
    "AIza[0-9A-Za-z\\-_]{35}"

    # GitHub Token
    "gh[pousr]_[A-Za-z0-9_]{36}"
    "github[_-]?token['\"]?\s*[:=]\s*['\"]?[A-Za-z0-9_-]{40}['\"]?"

    # Docker Hub
    "docker[_-]?password['\"]?\s*[:=]\s*['\"]?[A-Za-z0-9_-]{20,}['\"]?"

    # Generic patterns
    "password['\"]?\s*[:=]\s*['\"]?[A-Za-z0-9_@#$%^&*!-]{8,}['\"]?"
    "passwd['\"]?\s*[:=]\s*['\"]?[A-Za-z0-9_@#$%^&*!-]{8,}['\"]?"
    "token['\"]?\s*[:=]\s*['\"]?[A-Za-z0-9_-]{20,}['\"]?"

    # Private keys
    "-----BEGIN [A-Z]+ PRIVATE KEY-----"
    "-----BEGIN RSA PRIVATE KEY-----"
    "-----BEGIN OPENSSH PRIVATE KEY-----"

    # Connection strings
    "mongodb://[^\\s]+"
    "mysql://[^\\s]+"
    "postgres://[^\\s]+"
    "redis://[^\\s]+"

    # URLs with credentials
    "https?://[A-Za-z0-9_]+:[A-Za-z0-9_@#$%^&*!-]+@[^\\s]+"
)

# Whitelist patterns (common false positives)
WHITELIST_PATTERNS=(
    "example\\.com"
    "localhost"
    "127\\.0\\.0\\.1"
    "test[_-]?password"
    "dummy[_-]?token"
    "fake[_-]?key"
    "placeholder"
    "YOUR_API_KEY"
    "INSERT_TOKEN_HERE"
    "\\$\\{[^}]+\\}"  # Environment variable placeholders
    "\\*{5,}"        # Asterisks (masked values)
    "x{5,}"          # Repeated x's
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

log_secret() {
    echo -e "${RED}🔑${END} ${BOLD}SECRET DETECTED:${END} $*" >&2
    FOUND_SECRETS=true
}

# Function to show help
show_help() {
    cat << EOF
Secret Detector - Git Hook Utility

USAGE:
    secret-detector.sh [OPTIONS] <file1> [file2] ...

OPTIONS:
    -h, --help          Show this help message and exit
    -q, --quiet         Suppress informational output
    -v, --verbose       Show detailed detection information
    -c, --config FILE   Use custom configuration file
    --no-color          Disable colored output
    --staged-only       Only check staged files (git hook mode)

CONFIGURATION:
    The script looks for patterns in ~/.githooks-config.yml or uses built-in defaults.

    Example config file structure:
    secret_patterns:
      - "api[_-]?key.*[A-Za-z0-9_-]{20,}"
      - "password.*[A-Za-z0-9_@#\$%^&*!-]{8,}"

    whitelist_patterns:
      - "example\\.com"
      - "test[_-]?password"

EXAMPLES:
    secret-detector.sh file1.txt file2.py
    secret-detector.sh --verbose --config /path/to/config.yml *.js
    secret-detector.sh --staged-only  # For git pre-commit hook

EXIT CODES:
    0 - No secrets detected
    1 - Secrets detected
    2 - Script usage error
EOF
}

# Function to load patterns from config file
load_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        if [[ "$VERBOSE" == true ]]; then
            log_warning "Config file not found: $config_file, using default patterns"
        fi
        return 0
    fi

    log_info "Loading configuration from: $config_file"

    # Simple YAML parsing for secret_patterns and whitelist_patterns
    # This is basic and assumes well-formed YAML
    local in_secret_patterns=false
    local in_whitelist_patterns=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        if [[ "$line" =~ ^secret_patterns: ]]; then
            in_secret_patterns=true
            in_whitelist_patterns=false
            DEFAULT_PATTERNS=()  # Clear default patterns
            continue
        elif [[ "$line" =~ ^whitelist_patterns: ]]; then
            in_secret_patterns=false
            in_whitelist_patterns=true
            WHITELIST_PATTERNS=()  # Clear default whitelist
            continue
        elif [[ "$line" =~ ^[[:alpha:]_] ]]; then
            # New top-level key, exit current section
            in_secret_patterns=false
            in_whitelist_patterns=false
            continue
        fi

        # Parse pattern lines (expecting "  - pattern" format)
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(.*) ]]; then
            local pattern="${BASH_REMATCH[1]}"
            # Remove surrounding quotes if present
            pattern="${pattern#\"}"
            pattern="${pattern%\"}"
            pattern="${pattern#\'}"
            pattern="${pattern%\'}"

            if [[ "$in_secret_patterns" == true ]]; then
                DEFAULT_PATTERNS+=("$pattern")
            elif [[ "$in_whitelist_patterns" == true ]]; then
                WHITELIST_PATTERNS+=("$pattern")
            fi
        fi
    done < "$config_file"

    if [[ "$VERBOSE" == true ]]; then
        log_info "Loaded ${#DEFAULT_PATTERNS[@]} secret patterns and ${#WHITELIST_PATTERNS[@]} whitelist patterns"
    fi
}

# Function to check if a match should be whitelisted
is_whitelisted() {
    local match="$1"
    local file="$2"

    # Check against whitelist patterns
    for pattern in "${WHITELIST_PATTERNS[@]}"; do
        if [[ "$match" =~ $pattern ]]; then
            if [[ "$VERBOSE" == true ]]; then
                log_info "Whitelisted match in $file: $match"
            fi
            return 0
        fi
    done

    # Check if file is in .git directory
    if [[ "$file" =~ ^\.git/ ]]; then
        return 0
    fi

    # Check for common non-secret files
    local basename
    basename=$(basename "$file")
    if [[ "$basename" =~ \.(md|txt|rst|log)$ ]]; then
        # Be more lenient with documentation files
        if [[ "$match" =~ (example|sample|demo|test) ]]; then
            return 0
        fi
    fi

    return 1
}

# Function to scan a single file for secrets
scan_file() {
    local file="$1"
    local found_in_file=false

    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi

    # Check if file is binary
    if file "$file" | grep -q "binary"; then
        if [[ "$VERBOSE" == true ]]; then
            log_info "Skipping binary file: $file"
        fi
        return 0
    fi

    log_info "Scanning: $file"

    # Scan file with each pattern
    for pattern in "${DEFAULT_PATTERNS[@]}"; do
        local matches
        if matches=$(grep -nE "$pattern" "$file" 2>/dev/null); then
            while IFS= read -r match_line; do
                local line_number match_content
                line_number=$(echo "$match_line" | cut -d: -f1)
                match_content=$(echo "$match_line" | cut -d: -f2-)

                # Extract the actual matched content
                local matched_text
                if matched_text=$(echo "$match_content" | grep -oE "$pattern" | head -1); then
                    if ! is_whitelisted "$matched_text" "$file"; then
                        log_secret "$file:$line_number - Potential secret: ${YELLOW}$matched_text${END}"
                        if [[ "$VERBOSE" == true ]]; then
                            echo -e "    ${BLUE}Context:${END} $match_content"
                        fi
                        found_in_file=true
                    fi
                fi
            done <<< "$matches"
        fi
    done

    if [[ "$found_in_file" == false && "$VERBOSE" == true ]]; then
        log_success "Clean: $file"
    fi

    return 0
}

# Function to get staged files (for git hook mode)
get_staged_files() {
    git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true
}

# Function to scan multiple files
scan_files() {
    local files=("$@")

    if [[ ${#files[@]} -eq 0 ]]; then
        log_error "No files provided for scanning"
        return 2
    fi

    log_info "Starting secret detection scan on ${#files[@]} files"

    for file in "${files[@]}"; do
        scan_file "$file"
    done

    return 0
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
            -c|--config)
                if [[ -z "${2:-}" ]]; then
                    log_error "Config file path required for --config option"
                    exit 2
                fi
                CONFIG_FILE="$2"
                shift 2
                ;;
            --no-color)
                USE_COLOR=false
                shift
                ;;
            --staged-only)
                STAGED_ONLY=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                show_help
                exit 2
                ;;
            *)
                FILES+=("$1")
                shift
                ;;
        esac
    done
}

# Main function
main() {
    local FILES=()

    # Parse arguments
    parse_args "$@"

    # Set up colors
    if [[ "$USE_COLOR" == false ]] || [[ ! -t 1 ]]; then
        disable_colors
    fi

    # Determine config file
    local config_file="${CONFIG_FILE:-$DEFAULT_CONFIG_FILE}"

    # Load configuration
    load_config "$config_file"

    # Get files to scan
    if [[ "$STAGED_ONLY" == true ]]; then
        mapfile -t FILES < <(get_staged_files)
        if [[ ${#FILES[@]} -eq 0 ]]; then
            log_info "No staged files to scan"
            exit 0
        fi
        log_info "Scanning ${#FILES[@]} staged files"
    elif [[ ${#FILES[@]} -eq 0 ]]; then
        log_error "No files specified for scanning"
        show_help
        exit 2
    fi

    # Perform scan
    scan_files "${FILES[@]}"

    # Print summary
    if [[ "$FOUND_SECRETS" == true ]]; then
        echo ""
        log_error "🚨 SECRETS DETECTED! Please review and remove sensitive information before committing."
        echo -e "${YELLOW}💡 Tip: Use environment variables, secret management systems, or .env files (excluded from git)${END}"
        exit 1
    else
        if [[ "$QUIET" != true ]]; then
            echo ""
            log_success "🔒 No secrets detected. All clear!"
        fi
        exit 0
    fi
}

# Run main function with all arguments
main "$@"
