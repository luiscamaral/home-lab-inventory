#!/bin/bash
#
# File Checks - Git Hook Utility
# Performs various file type and size validations for git commits.
#
# Usage:
#   file-checks.sh [options] <file1> [file2] ...
#   file-checks.sh --help
#
# Options:
#   -h, --help              Show this help message and exit
#   -q, --quiet             Suppress informational output
#   -v, --verbose           Show detailed check information
#   -c, --config FILE       Use custom configuration file
#   --no-color              Disable colored output
#   --staged-only           Only check staged files (git hook mode)
#   --max-size SIZE         Maximum file size in bytes (default: 100MB)
#   --check-encoding        Check file encoding
#   --check-line-endings    Check line endings consistency
#   --allow-binary          Allow binary files (default: warn only)
#
# Exit codes:
#   0 - All files pass checks
#   1 - One or more files fail checks
#   2 - Script usage error
#
# Configuration:
#   The script uses ~/.githooks-config.yml for allowed/blocked file patterns
#   and size limits. It also has sensible defaults built-in.
#

set -euo pipefail

# Default configuration
VERBOSE=false
QUIET=false
USE_COLOR=true
STAGED_ONLY=false
CONFIG_FILE="$HOME/.githooks-config.yml"
MAX_FILE_SIZE=$((100 * 1024 * 1024))  # 100MB in bytes
CHECK_ENCODING=false
CHECK_LINE_ENDINGS=false
ALLOW_BINARY=true  # true = warn, false = error
FAILED_CHECKS=false

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

# Default blocked file patterns
BLOCKED_PATTERNS=(
    # Temporary files
    ".*~$"
    ".*\\.tmp$"
    ".*\\.temp$"
    ".*\\.swp$"
    ".*\\.swo$"
    "\\.DS_Store$"
    "Thumbs\\.db$"

    # IDE files (unless explicitly allowed)
    "\\.vscode/.*"
    "\\.idea/.*"
    ".*\\.iml$"

    # Build artifacts
    ".*\\.class$"
    ".*\\.pyc$"
    ".*\\.pyo$"
    "__pycache__/.*"
    "node_modules/.*"
    "target/.*"
    "build/.*"
    "dist/.*"
    "*.log"

    # Archives (usually too large)
    ".*\\.zip$"
    ".*\\.tar\\.gz$"
    ".*\\.tgz$"
    ".*\\.rar$"
    ".*\\.7z$"

    # Large binary files
    ".*\\.iso$"
    ".*\\.dmg$"
    ".*\\.exe$"
    ".*\\.msi$"
    ".*\\.deb$"
    ".*\\.rpm$"
)

# File patterns that are allowed to be large
LARGE_FILE_ALLOWED_PATTERNS=(
    ".*\\.md$"
    ".*\\.txt$"
    ".*\\.json$"
    ".*\\.yml$"
    ".*\\.yaml$"
    "LICENSE.*"
    "README.*"
    "CHANGELOG.*"
)

# Binary file patterns (will be checked but allowed with warning)
BINARY_PATTERNS=(
    ".*\\.pdf$"
    ".*\\.png$"
    ".*\\.jpg$"
    ".*\\.jpeg$"
    ".*\\.gif$"
    ".*\\.ico$"
    ".*\\.svg$"
    ".*\\.webp$"
    ".*\\.mp3$"
    ".*\\.mp4$"
    ".*\\.avi$"
    ".*\\.mov$"
    ".*\\.woff$"
    ".*\\.woff2$"
    ".*\\.ttf$"
    ".*\\.eot$"
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
    FAILED_CHECKS=true
}

log_detail() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "  ${BLUE}→${END} $*"
    fi
}

# Function to show help
show_help() {
    cat << EOF
File Checks - Git Hook Utility

USAGE:
    file-checks.sh [OPTIONS] <file1> [file2] ...

OPTIONS:
    -h, --help              Show this help message and exit
    -q, --quiet             Suppress informational output
    -v, --verbose           Show detailed check information
    -c, --config FILE       Use custom configuration file
    --no-color              Disable colored output
    --staged-only           Only check staged files (git hook mode)
    --max-size SIZE         Maximum file size in bytes (default: 100MB)
    --check-encoding        Check file encoding (UTF-8 recommended)
    --check-line-endings    Check line endings consistency
    --allow-binary          Allow binary files (default: warn only)

CHECKS PERFORMED:
    ✓ File size limits
    ✓ Blocked file patterns (temp files, build artifacts)
    ✓ Binary file detection
    ✓ File permissions
    ✓ File encoding (optional)
    ✓ Line endings consistency (optional)
    ✓ Git LFS tracking for large files

CONFIGURATION:
    Uses ~/.githooks-config.yml for custom patterns:

    blocked_file_patterns:
      - ".*\\\\.tmp$"
      - "node_modules/.*"

    allowed_large_files:
      - ".*\\\\.md$"
      - "documentation/.*"

    max_file_size: 104857600  # 100MB in bytes

EXAMPLES:
    file-checks.sh *.js *.py
    file-checks.sh --staged-only --check-encoding
    file-checks.sh --max-size 52428800 --verbose large-file.txt

EXIT CODES:
    0 - All files pass checks
    1 - One or more files fail checks
    2 - Script usage error
EOF
}

# Function to format file size
format_size() {
    local bytes=$1
    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes}B"
    elif [[ $bytes -lt 1048576 ]]; then
        echo "$((bytes / 1024))KB"
    elif [[ $bytes -lt 1073741824 ]]; then
        echo "$((bytes / 1048576))MB"
    else
        echo "$((bytes / 1073741824))GB"
    fi
}

# Function to check if file matches pattern
matches_pattern() {
    local file="$1"
    local pattern="$2"
    [[ "$file" =~ $pattern ]]
}

# Function to check if file is blocked
is_blocked_file() {
    local file="$1"

    for pattern in "${BLOCKED_PATTERNS[@]}"; do
        if matches_pattern "$file" "$pattern"; then
            log_detail "File matches blocked pattern: $pattern"
            return 0
        fi
    done

    return 1
}

# Function to check if large file is allowed
is_large_file_allowed() {
    local file="$1"

    for pattern in "${LARGE_FILE_ALLOWED_PATTERNS[@]}"; do
        if matches_pattern "$file" "$pattern"; then
            log_detail "Large file allowed by pattern: $pattern"
            return 0
        fi
    done

    return 1
}

# Function to check if file is binary
is_binary_file() {
    local file="$1"

    # Check by extension first
    for pattern in "${BINARY_PATTERNS[@]}"; do
        if matches_pattern "$file" "$pattern"; then
            return 0
        fi
    done

    # Check file content
    if file "$file" | grep -q "binary"; then
        return 0
    fi

    return 1
}

# Function to check file encoding
check_file_encoding() {
    local file="$1"

    if ! file --mime-encoding "$file" | grep -q "utf-8"; then
        local encoding
        encoding=$(file --mime-encoding "$file" | cut -d: -f2 | xargs)
        log_warning "File $file has non-UTF-8 encoding: $encoding"
        log_detail "Consider converting to UTF-8 for better compatibility"
    else
        log_detail "File encoding: UTF-8 ✓"
    fi
}

# Function to check line endings
check_line_endings() {
    local file="$1"

    # Skip binary files
    if is_binary_file "$file"; then
        return 0
    fi

    local crlf_count lf_count cr_count
    crlf_count=$(grep -c $'\r\n' "$file" 2>/dev/null || echo "0")
    lf_count=$(grep -c $'\n' "$file" 2>/dev/null || echo "0")
    cr_count=$(grep -c $'\r' "$file" 2>/dev/null || echo "0")

    # Adjust counts (CRLF contains LF)
    lf_count=$((lf_count - crlf_count))
    cr_count=$((cr_count - crlf_count))

    local total_lines=$((crlf_count + lf_count + cr_count))

    if [[ $total_lines -gt 0 ]]; then
        if [[ $crlf_count -gt 0 && $lf_count -gt 0 ]]; then
            log_warning "File $file has mixed line endings (CRLF: $crlf_count, LF: $lf_count)"
            log_detail "Consider normalizing line endings"
        elif [[ $crlf_count -gt 0 ]]; then
            log_detail "Line endings: CRLF (Windows)"
        elif [[ $lf_count -gt 0 ]]; then
            log_detail "Line endings: LF (Unix/Linux/macOS)"
        elif [[ $cr_count -gt 0 ]]; then
            log_warning "File $file uses CR line endings (classic Mac)"
            log_detail "Consider using LF or CRLF"
        fi
    fi
}

# Function to check if file should be in Git LFS
check_git_lfs() {
    local file="$1"
    local size="$2"

    # Check if Git LFS is available
    if ! command -v git-lfs >/dev/null 2>&1; then
        return 0
    fi

    # Check if file is already tracked by Git LFS
    if git lfs ls-files | grep -q "$(basename "$file")"; then
        log_detail "File is tracked by Git LFS ✓"
        return 0
    fi

    # Check if large binary file should be in LFS
    if [[ $size -gt $((10 * 1024 * 1024)) ]] && is_binary_file "$file"; then
        log_warning "Large binary file should be tracked by Git LFS: $(format_size "$size")"
        log_detail "Run: git lfs track \"$file\" && git add \"$file\""
        return 1
    fi

    return 0
}

# Function to load configuration
load_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        if [[ "$VERBOSE" == true ]]; then
            log_info "Config file not found: $config_file, using defaults"
        fi
        return 0
    fi

    log_info "Loading configuration from: $config_file"

    # Simple YAML parsing (basic implementation)
    local in_blocked_patterns=false
    local in_allowed_large=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        if [[ "$line" =~ ^blocked_file_patterns: ]]; then
            in_blocked_patterns=true
            in_allowed_large=false
            BLOCKED_PATTERNS=()  # Clear defaults
            continue
        elif [[ "$line" =~ ^allowed_large_files: ]]; then
            in_blocked_patterns=false
            in_allowed_large=true
            LARGE_FILE_ALLOWED_PATTERNS=()  # Clear defaults
            continue
        elif [[ "$line" =~ ^max_file_size:[[:space:]]*([0-9]+) ]]; then
            MAX_FILE_SIZE="${BASH_REMATCH[1]}"
            log_detail "Config: max_file_size = $(format_size "$MAX_FILE_SIZE")"
            continue
        elif [[ "$line" =~ ^[[:alpha:]_] ]]; then
            # New top-level key, exit current section
            in_blocked_patterns=false
            in_allowed_large=false
            continue
        fi

        # Parse pattern lines
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(.*) ]]; then
            local pattern="${BASH_REMATCH[1]}"
            # Remove surrounding quotes if present
            pattern="${pattern#\"}"
            pattern="${pattern%\"}"
            pattern="${pattern#\'}"
            pattern="${pattern%\'}"

            if [[ "$in_blocked_patterns" == true ]]; then
                BLOCKED_PATTERNS+=("$pattern")
            elif [[ "$in_allowed_large" == true ]]; then
                LARGE_FILE_ALLOWED_PATTERNS+=("$pattern")
            fi
        fi
    done < "$config_file"

    if [[ "$VERBOSE" == true ]]; then
        log_info "Loaded ${#BLOCKED_PATTERNS[@]} blocked patterns and ${#LARGE_FILE_ALLOWED_PATTERNS[@]} large file patterns"
    fi
}

# Function to check a single file
check_file() {
    local file="$1"
    local file_passed=true

    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi

    log_info "Checking: $file"

    # Get file size
    local file_size
    if [[ "$OSTYPE" == "darwin"* ]]; then
        file_size=$(stat -f%z "$file" 2>/dev/null || echo "0")
    else
        file_size=$(stat -c%s "$file" 2>/dev/null || echo "0")
    fi

    log_detail "File size: $(format_size "$file_size")"

    # Check if file is blocked
    if is_blocked_file "$file"; then
        log_error "Blocked file type: $file"
        log_detail "This file type should not be committed to the repository"
        file_passed=false
    fi

    # Check file size
    if [[ $file_size -gt $MAX_FILE_SIZE ]]; then
        if is_large_file_allowed "$file"; then
            log_warning "Large file allowed: $file ($(format_size "$file_size"))"
        else
            log_error "File too large: $file ($(format_size "$file_size"), limit: $(format_size "$MAX_FILE_SIZE"))"
            log_detail "Consider using Git LFS for large files"
            file_passed=false
        fi
    fi

    # Check binary files
    if is_binary_file "$file"; then
        if [[ "$ALLOW_BINARY" == true ]]; then
            log_warning "Binary file detected: $file"
            log_detail "Ensure this binary file should be in the repository"
        else
            log_error "Binary file not allowed: $file"
            file_passed=false
        fi

        # Check Git LFS for large binary files
        check_git_lfs "$file" "$file_size"
    else
        log_detail "File type: Text ✓"
    fi

    # Check file encoding if requested
    if [[ "$CHECK_ENCODING" == true ]]; then
        check_file_encoding "$file"
    fi

    # Check line endings if requested
    if [[ "$CHECK_LINE_ENDINGS" == true ]]; then
        check_line_endings "$file"
    fi

    # Check file permissions
    if [[ -x "$file" ]]; then
        local filename
        filename=$(basename "$file")
        if [[ ! "$filename" =~ \.(sh|py|pl|rb|js)$ ]] && [[ ! "$filename" == "Makefile" ]]; then
            log_warning "Executable permission on non-script file: $file"
            log_detail "Consider: chmod -x \"$file\""
        else
            log_detail "File permissions: Executable (appropriate for script) ✓"
        fi
    else
        log_detail "File permissions: Regular file ✓"
    fi

    if [[ "$file_passed" == true && "$VERBOSE" == true ]]; then
        log_success "Passed all checks: $file"
    fi

    return $([ "$file_passed" == true ] && echo 0 || echo 1)
}

# Function to get staged files
get_staged_files() {
    git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true
}

# Function to check multiple files
check_files() {
    local files=("$@")

    if [[ ${#files[@]} -eq 0 ]]; then
        log_error "No files provided for checking"
        return 2
    fi

    log_info "Starting file checks on ${#files[@]} files"
    log_detail "Max file size: $(format_size "$MAX_FILE_SIZE")"

    local total_files=${#files[@]}
    local checked_files=0

    for file in "${files[@]}"; do
        check_file "$file"
        ((checked_files++))

        if [[ "$VERBOSE" == true ]]; then
            log_detail "Progress: $checked_files/$total_files files checked"
        fi
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
            --max-size)
                if [[ -z "${2:-}" ]] || [[ ! "${2:-}" =~ ^[0-9]+$ ]]; then
                    log_error "Valid file size in bytes required for --max-size option"
                    exit 2
                fi
                MAX_FILE_SIZE="$2"
                shift 2
                ;;
            --check-encoding)
                CHECK_ENCODING=true
                shift
                ;;
            --check-line-endings)
                CHECK_LINE_ENDINGS=true
                shift
                ;;
            --allow-binary)
                ALLOW_BINARY=true
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

    # Load configuration
    load_config "$CONFIG_FILE"

    # Get files to check
    if [[ "$STAGED_ONLY" == true ]]; then
        mapfile -t FILES < <(get_staged_files)
        if [[ ${#FILES[@]} -eq 0 ]]; then
            log_info "No staged files to check"
            exit 0
        fi
        log_info "Checking ${#FILES[@]} staged files"
    elif [[ ${#FILES[@]} -eq 0 ]]; then
        log_error "No files specified for checking"
        show_help
        exit 2
    fi

    # Perform checks
    check_files "${FILES[@]}"

    # Print summary
    if [[ "$FAILED_CHECKS" == true ]]; then
        echo ""
        log_error "🚨 File checks failed! Please fix the issues above before committing."
        echo -e "${YELLOW}💡 Tips:${END}"
        echo "  - Remove temporary and build files"
        echo "  - Use Git LFS for large binary files"
        echo "  - Check file permissions and encoding"
        exit 1
    else
        if [[ "$QUIET" != true ]]; then
            echo ""
            log_success "🎉 All file checks passed!"
        fi
        exit 0
    fi
}

# Run main function with all arguments
main "$@"
