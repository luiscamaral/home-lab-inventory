#!/bin/bash
# SSH Multiplexing Helper for Dockermaster
# Part of dockermaster-recovery documentation framework
# Created: 2025-08-28

set -euo pipefail

# Configuration
DOCKERMASTER_HOST="dockermaster"
SSH_CONTROL_PATH="$HOME/.ssh/master-%r@%h:%p"
SSH_CONTROL_PERSIST="10m"
SCRIPT_NAME=$(basename "$0")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [COMMAND] [ARGS...]

SSH Multiplexing Helper for Dockermaster Documentation Framework

Commands:
    connect     - Establish persistent SSH connection to dockermaster
    disconnect  - Close persistent SSH connection
    status      - Check connection status
    exec        - Execute command on dockermaster via multiplexed connection
    shell       - Open interactive shell via multiplexed connection
    test        - Test connection and multiplexing functionality
    help        - Show this help message

Examples:
    $SCRIPT_NAME connect                    # Establish connection
    $SCRIPT_NAME exec "docker ps"           # Execute command
    $SCRIPT_NAME exec "ls /nfs/dockermaster/docker/"  # List services
    $SCRIPT_NAME shell                      # Interactive session
    $SCRIPT_NAME status                     # Check if connected
    $SCRIPT_NAME disconnect                 # Close connection

Configuration:
    Host: $DOCKERMASTER_HOST
    Control Path: $SSH_CONTROL_PATH
    Persist Time: $SSH_CONTROL_PERSIST

Notes:
    - Connection persists for $SSH_CONTROL_PERSIST after last use
    - Multiple sessions share the same connection
    - Significantly faster for automation scripts
    - Use 'connect' before running documentation automation tools
EOF
}

# Check if SSH multiplexing is configured
check_ssh_config() {
    local ssh_config="$HOME/.ssh/config"

    if [[ ! -f "$ssh_config" ]]; then
        log_error "SSH config file not found at $ssh_config"
        return 1
    fi

    if ! grep -q "Host $DOCKERMASTER_HOST" "$ssh_config"; then
        log_error "Host $DOCKERMASTER_HOST not found in SSH config"
        log_info "Please add the following to your SSH config:"
        cat << EOF

Host $DOCKERMASTER_HOST
    ControlMaster auto
    ControlPath $SSH_CONTROL_PATH
    ControlPersist $SSH_CONTROL_PERSIST
    ServerAliveInterval 60
    ServerAliveCountMax 3

EOF
        return 1
    fi

    return 0
}

# Get control socket path for the connection
get_control_socket() {
    # Replace SSH control path variables
    echo "$SSH_CONTROL_PATH" | sed "s/%r/$USER/g; s/%h/$DOCKERMASTER_HOST/g; s/%p/22/g"
}

# Check connection status
check_connection_status() {
    local control_socket
    control_socket=$(get_control_socket)

    if [[ -S "$control_socket" ]]; then
        # Check if the connection is actually working
        if ssh -O check "$DOCKERMASTER_HOST" 2>/dev/null; then
            return 0  # Connected
        else
            # Socket exists but connection is dead, clean it up
            rm -f "$control_socket" 2>/dev/null || true
            return 1  # Not connected
        fi
    else
        return 1  # Not connected
    fi
}

# Establish SSH connection
connect_ssh() {
    log_info "Establishing persistent SSH connection to $DOCKERMASTER_HOST..."

    if check_connection_status; then
        log_warning "Connection already established"
        return 0
    fi

    # Create SSH directory if it doesn't exist
    mkdir -p "$(dirname "$(get_control_socket)")"

    # Establish master connection in background
    if ssh -fN "$DOCKERMASTER_HOST" 2>/dev/null; then
        # Wait a moment for connection to establish
        sleep 2

        if check_connection_status; then
            log_success "SSH connection established successfully"
            log_info "Connection will persist for $SSH_CONTROL_PERSIST after last use"
            return 0
        else
            log_error "Failed to verify connection status"
            return 1
        fi
    else
        log_error "Failed to establish SSH connection"
        return 1
    fi
}

# Close SSH connection
disconnect_ssh() {
    log_info "Closing persistent SSH connection to $DOCKERMASTER_HOST..."

    if ! check_connection_status; then
        log_warning "No active connection found"
        return 0
    fi

    if ssh -O exit "$DOCKERMASTER_HOST" 2>/dev/null; then
        log_success "SSH connection closed successfully"

        # Clean up any remaining socket files
        local control_socket
        control_socket=$(get_control_socket)
        rm -f "$control_socket" 2>/dev/null || true

        return 0
    else
        log_error "Failed to close SSH connection"
        return 1
    fi
}

# Show connection status
show_status() {
    log_info "Checking SSH connection status for $DOCKERMASTER_HOST..."

    if check_connection_status; then
        log_success "Connection is active and healthy"

        # Show connection details
        local control_socket
        control_socket=$(get_control_socket)

        if [[ -S "$control_socket" ]]; then
            log_info "Control socket: $control_socket"
            log_info "Socket created: $(stat -f "%Sm" "$control_socket" 2>/dev/null || echo "Unknown")"
        fi

        # Test basic command
        log_info "Testing connection with hostname command..."
        if ssh "$DOCKERMASTER_HOST" "hostname" 2>/dev/null; then
            log_success "Connection test passed"
        else
            log_warning "Connection test failed"
        fi

        return 0
    else
        log_warning "No active connection found"
        return 1
    fi
}

# Execute command on dockermaster
execute_command() {
    local cmd="$*"

    if [[ -z "$cmd" ]]; then
        log_error "No command specified"
        usage
        exit 1
    fi

    log_info "Executing command on $DOCKERMASTER_HOST: $cmd"

    if ! check_connection_status; then
        log_warning "No active connection found, establishing new connection..."
        if ! connect_ssh; then
            log_error "Failed to establish connection"
            exit 1
        fi
    fi

    # Execute the command
    ssh "$DOCKERMASTER_HOST" "$cmd"
}

# Open interactive shell
open_shell() {
    log_info "Opening interactive shell on $DOCKERMASTER_HOST..."

    if ! check_connection_status; then
        log_warning "No active connection found, establishing new connection..."
        if ! connect_ssh; then
            log_error "Failed to establish connection"
            exit 1
        fi
    fi

    # Open interactive shell
    ssh -t "$DOCKERMASTER_HOST"
}

# Test SSH multiplexing functionality
test_connection() {
    log_info "Testing SSH multiplexing functionality..."

    # Check SSH config
    if ! check_ssh_config; then
        log_error "SSH configuration check failed"
        return 1
    fi

    log_success "SSH configuration check passed"

    # Test connection establishment
    if ! connect_ssh; then
        log_error "Connection establishment test failed"
        return 1
    fi

    # Test command execution
    log_info "Testing command execution..."
    if execute_command "echo 'SSH multiplexing test successful'" >/dev/null; then
        log_success "Command execution test passed"
    else
        log_error "Command execution test failed"
        return 1
    fi

    # Test performance (multiple commands using same connection)
    log_info "Testing connection reuse performance..."
    local start_time end_time
    start_time=$(date +%s.%N)

    for i in {1..5}; do
        execute_command "echo 'Test $i'" >/dev/null
    done

    end_time=$(date +%s.%N)
    local duration
    duration=$(echo "$end_time - $start_time" | bc -l)

    log_success "Performance test completed in ${duration}s (5 commands)"
    log_info "SSH multiplexing is working correctly"

    return 0
}

# Main function
main() {
    # Check if SSH config is properly configured
    if [[ "${1:-}" != "help" ]] && [[ "${1:-}" != "test" ]]; then
        if ! check_ssh_config; then
            exit 1
        fi
    fi

    case "${1:-help}" in
        "connect")
            connect_ssh
            ;;
        "disconnect")
            disconnect_ssh
            ;;
        "status")
            show_status
            ;;
        "exec")
            shift
            execute_command "$@"
            ;;
        "shell")
            open_shell
            ;;
        "test")
            test_connection
            ;;
        "help"|"-h"|"--help")
            usage
            ;;
        *)
            log_error "Unknown command: ${1:-}"
            usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
