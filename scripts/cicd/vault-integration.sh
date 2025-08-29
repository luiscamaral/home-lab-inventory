#!/bin/bash
# Vault Integration Script for Dockermaster CI/CD
# This script provides Vault authentication and secret management for CI/CD pipelines

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_ADDR="${VAULT_ADDR:-http://vault.d.lcamaral.com}"
VAULT_ROLE_ID="${VAULT_ROLE_ID:-}"
VAULT_SECRET_ID="${VAULT_SECRET_ID:-}"
VAULT_TOKEN_FILE="${VAULT_TOKEN_FILE:-/tmp/vault-token}"
VAULT_AUTH_METHOD="${VAULT_AUTH_METHOD:-approle}"
SECRET_BASE_PATH="${SECRET_BASE_PATH:-secret/dockermaster}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_debug() {
    if [[ "$LOG_LEVEL" == "DEBUG" ]]; then
        echo -e "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
    fi
}

# Usage information
usage() {
    cat << EOF
Usage: $0 COMMAND [OPTIONS]

Vault integration script for dockermaster CI/CD pipelines.

COMMANDS:
    auth                         Authenticate with Vault and get token
    get-secret PATH              Get secret from Vault
    set-secret PATH KEY=VALUE    Set secret in Vault
    list-secrets [PATH]          List secrets at path
    revoke-token                 Revoke current token
    health-check                 Check Vault connectivity and health
    setup-approle SERVICE       Setup AppRole for service
    generate-env SERVICE         Generate .env file from Vault secrets

OPTIONS:
    -h, --help                   Show this help message
    -v, --verbose                Enable verbose output
    -t, --token TOKEN            Use specific Vault token
    -a, --addr ADDRESS           Vault server address
    -m, --method METHOD          Auth method (approle, token)
    -f, --format FORMAT          Output format (json, env, yaml)
    -o, --output FILE            Output to file instead of stdout
    --role-id ID                 AppRole role ID
    --secret-id ID               AppRole secret ID
    --force                      Force operation without confirmation

EXAMPLES:
    $0 auth                                    # Authenticate with Vault
    $0 get-secret github-runner/github-token  # Get specific secret
    $0 set-secret vault/root-token token=hvs.xxx  # Set secret
    $0 generate-env github-runner              # Generate .env file
    $0 setup-approle calibre-server          # Setup AppRole for service

ENVIRONMENT VARIABLES:
    VAULT_ADDR              Vault server address
    VAULT_TOKEN             Vault authentication token
    VAULT_ROLE_ID           AppRole role ID
    VAULT_SECRET_ID         AppRole secret ID
    VAULT_AUTH_METHOD       Authentication method
    SECRET_BASE_PATH        Base path for secrets

EXIT CODES:
    0    Success
    1    General error
    2    Vault unavailable
    3    Authentication failed
    4    Secret not found
    5    Permission denied
    10   Invalid arguments
EOF
}

# Parse command line arguments
parse_args() {
    COMMAND=""
    VERBOSE=false
    TOKEN=""
    ADDR=""
    METHOD=""
    OUTPUT_FORMAT="json"
    OUTPUT_FILE=""
    ROLE_ID=""
    SECRET_ID=""
    FORCE=false
    ARGS=()

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                LOG_LEVEL="DEBUG"
                shift
                ;;
            -t|--token)
                TOKEN="$2"
                shift 2
                ;;
            -a|--addr)
                ADDR="$2"
                VAULT_ADDR="$2"
                shift 2
                ;;
            -m|--method)
                METHOD="$2"
                shift 2
                ;;
            -f|--format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --role-id)
                ROLE_ID="$2"
                shift 2
                ;;
            --secret-id)
                SECRET_ID="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                exit 10
                ;;
            *)
                if [[ -z "$COMMAND" ]]; then
                    COMMAND="$1"
                else
                    ARGS+=("$1")
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$COMMAND" ]]; then
        log_error "Command is required"
        usage
        exit 10
    fi

    # Override environment variables with command line options
    [[ -n "$TOKEN" ]] && VAULT_TOKEN="$TOKEN"
    [[ -n "$METHOD" ]] && VAULT_AUTH_METHOD="$METHOD"
    [[ -n "$ROLE_ID" ]] && VAULT_ROLE_ID="$ROLE_ID"
    [[ -n "$SECRET_ID" ]] && VAULT_SECRET_ID="$SECRET_ID"
}

# Check if Vault is available
check_vault_availability() {
    log_debug "Checking Vault availability at $VAULT_ADDR"

    if ! curl -s -f --connect-timeout 5 "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
        log_error "Vault is not accessible at $VAULT_ADDR"
        return 2
    fi

    log_debug "Vault is accessible"
    return 0
}

# Authenticate with Vault
vault_auth() {
    log_info "Authenticating with Vault using method: $VAULT_AUTH_METHOD"

    case "$VAULT_AUTH_METHOD" in
        "approle")
            if [[ -z "$VAULT_ROLE_ID" ]] || [[ -z "$VAULT_SECRET_ID" ]]; then
                log_error "VAULT_ROLE_ID and VAULT_SECRET_ID are required for AppRole authentication"
                return 3
            fi

            log_debug "Using AppRole authentication"

            local auth_response
            auth_response=$(curl -s -X POST \
                -d "{\"role_id\":\"$VAULT_ROLE_ID\",\"secret_id\":\"$VAULT_SECRET_ID\"}" \
                "$VAULT_ADDR/v1/auth/approle/login")

            if [[ $? -ne 0 ]]; then
                log_error "Failed to authenticate with Vault"
                return 3
            fi

            local auth_token
            auth_token=$(echo "$auth_response" | jq -r '.auth.client_token' 2>/dev/null)

            if [[ -z "$auth_token" ]] || [[ "$auth_token" == "null" ]]; then
                log_error "Failed to extract token from Vault response"
                log_debug "Response: $auth_response"
                return 3
            fi

            # Store token securely
            echo "$auth_token" > "$VAULT_TOKEN_FILE"
            chmod 600 "$VAULT_TOKEN_FILE"

            # Export for current session
            export VAULT_TOKEN="$auth_token"

            log_success "Successfully authenticated with Vault"
            ;;
        "token")
            if [[ -z "$VAULT_TOKEN" ]]; then
                log_error "VAULT_TOKEN is required for token authentication"
                return 3
            fi

            # Verify token
            local token_info
            token_info=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
                "$VAULT_ADDR/v1/auth/token/lookup-self")

            if [[ $? -ne 0 ]] || [[ $(echo "$token_info" | jq -r '.data.id' 2>/dev/null) == "null" ]]; then
                log_error "Invalid or expired Vault token"
                return 3
            fi

            log_success "Token authentication verified"
            ;;
        *)
            log_error "Unsupported authentication method: $VAULT_AUTH_METHOD"
            return 3
            ;;
    esac

    return 0
}

# Get secret from Vault
get_secret() {
    local secret_path="$1"
    local full_path="$SECRET_BASE_PATH/$secret_path"

    log_debug "Getting secret from path: $full_path"

    # Ensure we have a valid token
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        if [[ -f "$VAULT_TOKEN_FILE" ]]; then
            VAULT_TOKEN=$(cat "$VAULT_TOKEN_FILE")
            export VAULT_TOKEN
        else
            log_error "No Vault token available. Run 'auth' command first."
            return 3
        fi
    fi

    local response
    response=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/$full_path")

    if [[ $? -ne 0 ]]; then
        log_error "Failed to retrieve secret from $full_path"
        return 4
    fi

    # Check if secret exists
    if [[ $(echo "$response" | jq -r '.data' 2>/dev/null) == "null" ]]; then
        log_error "Secret not found at path: $full_path"
        log_debug "Response: $response"
        return 4
    fi

    local secret_data
    secret_data=$(echo "$response" | jq '.data.data // .data')

    # Format output
    case "$OUTPUT_FORMAT" in
        "json")
            echo "$secret_data" | jq .
            ;;
        "env")
            echo "$secret_data" | jq -r 'to_entries[] | "\(.key)=\(.value)"'
            ;;
        "yaml")
            echo "$secret_data" | jq -r 'to_entries[] | "\(.key): \(.value)"'
            ;;
        *)
            echo "$secret_data" | jq .
            ;;
    esac

    return 0
}

# Set secret in Vault
set_secret() {
    local secret_path="$1"
    shift
    local key_values=("$@")

    if [[ ${#key_values[@]} -eq 0 ]]; then
        log_error "At least one KEY=VALUE pair is required"
        return 10
    fi

    local full_path="$SECRET_BASE_PATH/$secret_path"

    log_debug "Setting secret at path: $full_path"

    # Ensure we have a valid token
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        if [[ -f "$VAULT_TOKEN_FILE" ]]; then
            VAULT_TOKEN=$(cat "$VAULT_TOKEN_FILE")
            export VAULT_TOKEN
        else
            log_error "No Vault token available. Run 'auth' command first."
            return 3
        fi
    fi

    # Build JSON payload
    local json_data="{\"data\":{"
    local first=true

    for kv in "${key_values[@]}"; do
        if [[ ! "$kv" =~ ^[^=]+=[^=]*$ ]]; then
            log_error "Invalid key=value format: $kv"
            return 10
        fi

        local key="${kv%%=*}"
        local value="${kv#*=}"

        if [[ "$first" == "true" ]]; then
            first=false
        else
            json_data+=","
        fi

        json_data+="\"$key\":\"$value\""
    done

    json_data+="}}"

    log_debug "JSON payload: $json_data"

    local response
    response=$(curl -s -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -d "$json_data" \
        "$VAULT_ADDR/v1/$full_path")

    if [[ $? -ne 0 ]]; then
        log_error "Failed to set secret at $full_path"
        return 1
    fi

    # Check for errors in response
    local errors
    errors=$(echo "$response" | jq -r '.errors[]' 2>/dev/null || echo "")

    if [[ -n "$errors" ]]; then
        log_error "Vault error: $errors"
        return 5
    fi

    log_success "Secret set successfully at $full_path"
    return 0
}

# List secrets at path
list_secrets() {
    local list_path="${1:-}"
    local full_path="$SECRET_BASE_PATH"

    if [[ -n "$list_path" ]]; then
        full_path="$SECRET_BASE_PATH/$list_path"
    fi

    log_debug "Listing secrets at path: $full_path"

    # Ensure we have a valid token
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        if [[ -f "$VAULT_TOKEN_FILE" ]]; then
            VAULT_TOKEN=$(cat "$VAULT_TOKEN_FILE")
            export VAULT_TOKEN
        else
            log_error "No Vault token available. Run 'auth' command first."
            return 3
        fi
    fi

    local response
    response=$(curl -s -X LIST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/$full_path")

    if [[ $? -ne 0 ]]; then
        log_error "Failed to list secrets at $full_path"
        return 4
    fi

    local keys
    keys=$(echo "$response" | jq -r '.data.keys[]?' 2>/dev/null)

    if [[ -z "$keys" ]]; then
        log_info "No secrets found at $full_path"
        return 0
    fi

    case "$OUTPUT_FORMAT" in
        "json")
            echo "$response" | jq '.data.keys'
            ;;
        *)
            echo "$keys"
            ;;
    esac

    return 0
}

# Generate .env file from Vault secrets
generate_env_file() {
    local service_name="$1"
    local service_path="$SECRET_BASE_PATH/$service_name"

    log_info "Generating .env file for service: $service_name"

    # Get secrets
    local secrets
    if ! secrets=$(OUTPUT_FORMAT=env get_secret "$service_name"); then
        log_error "Failed to retrieve secrets for $service_name"
        return 4
    fi

    # Prepare output
    local output_content="# Generated from Vault secrets
# Service: $service_name
# Generated at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# DO NOT EDIT MANUALLY - Changes will be overwritten

$secrets"

    # Output to file or stdout
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$output_content" > "$OUTPUT_FILE"
        chmod 600 "$OUTPUT_FILE"
        log_success "Environment file generated: $OUTPUT_FILE"
    else
        echo "$output_content"
    fi

    return 0
}

# Setup AppRole for service
setup_approle() {
    local service_name="$1"

    if [[ "$FORCE" != "true" ]]; then
        echo "This will create/update AppRole configuration for service: $service_name"
        read -p "Continue? (y/N): " -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "Operation cancelled"
            return 0
        fi
    fi

    log_info "Setting up AppRole for service: $service_name"

    # Ensure we have a valid token with sufficient permissions
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        if [[ -f "$VAULT_TOKEN_FILE" ]]; then
            VAULT_TOKEN=$(cat "$VAULT_TOKEN_FILE")
            export VAULT_TOKEN
        else
            log_error "No Vault token available. Run 'auth' command first."
            return 3
        fi
    fi

    # Create policy for service
    local policy_name="dockermaster-${service_name}"
    local policy_content="path \"$SECRET_BASE_PATH/$service_name/*\" {
  capabilities = [\"read\", \"list\"]
}

path \"$SECRET_BASE_PATH/$service_name\" {
  capabilities = [\"read\", \"list\"]
}"

    log_debug "Creating policy: $policy_name"

    local policy_response
    policy_response=$(curl -s -X PUT \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -d "{\"policy\":\"$policy_content\"}" \
        "$VAULT_ADDR/v1/sys/policies/acl/$policy_name")

    # Create AppRole
    local role_name="dockermaster-${service_name}"
    local role_config="{
        \"token_policies\": [\"$policy_name\"],
        \"token_ttl\": \"1h\",
        \"token_max_ttl\": \"4h\",
        \"secret_id_ttl\": \"10m\"
    }"

    log_debug "Creating AppRole: $role_name"

    local role_response
    role_response=$(curl -s -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -d "$role_config" \
        "$VAULT_ADDR/v1/auth/approle/role/$role_name")

    # Get role ID
    local role_id_response
    role_id_response=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/auth/approle/role/$role_name/role-id")

    local role_id
    role_id=$(echo "$role_id_response" | jq -r '.data.role_id')

    # Generate secret ID
    local secret_id_response
    secret_id_response=$(curl -s -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/auth/approle/role/$role_name/secret-id")

    local secret_id
    secret_id=$(echo "$secret_id_response" | jq -r '.data.secret_id')

    if [[ "$role_id" != "null" ]] && [[ "$secret_id" != "null" ]]; then
        log_success "AppRole setup completed for $service_name"
        echo
        echo "AppRole Credentials (store securely):"
        echo "Role ID: $role_id"
        echo "Secret ID: $secret_id"
        echo
        echo "Environment variables for CI/CD:"
        echo "VAULT_ROLE_ID=$role_id"
        echo "VAULT_SECRET_ID=$secret_id"
    else
        log_error "Failed to setup AppRole for $service_name"
        return 1
    fi

    return 0
}

# Health check
health_check() {
    log_info "Performing Vault health check"

    # Basic connectivity
    if ! check_vault_availability; then
        return 2
    fi

    # Get health status
    local health_response
    health_response=$(curl -s "$VAULT_ADDR/v1/sys/health")

    if [[ $? -ne 0 ]]; then
        log_error "Failed to get Vault health status"
        return 2
    fi

    case "$OUTPUT_FORMAT" in
        "json")
            echo "$health_response" | jq .
            ;;
        *)
            local initialized sealed
            initialized=$(echo "$health_response" | jq -r '.initialized')
            sealed=$(echo "$health_response" | jq -r '.sealed')

            echo "Vault Health Status:"
            echo "  Initialized: $initialized"
            echo "  Sealed: $sealed"
            echo "  Address: $VAULT_ADDR"

            if [[ "$initialized" == "true" ]] && [[ "$sealed" == "false" ]]; then
                log_success "Vault is healthy and operational"
            else
                log_warn "Vault may not be fully operational"
            fi
            ;;
    esac

    return 0
}

# Revoke current token
revoke_token() {
    log_info "Revoking current Vault token"

    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        if [[ -f "$VAULT_TOKEN_FILE" ]]; then
            VAULT_TOKEN=$(cat "$VAULT_TOKEN_FILE")
            export VAULT_TOKEN
        else
            log_warn "No Vault token found to revoke"
            return 0
        fi
    fi

    local response
    response=$(curl -s -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/auth/token/revoke-self")

    if [[ $? -eq 0 ]]; then
        log_success "Token revoked successfully"

        # Clean up token file
        if [[ -f "$VAULT_TOKEN_FILE" ]]; then
            rm -f "$VAULT_TOKEN_FILE"
        fi

        unset VAULT_TOKEN
    else
        log_error "Failed to revoke token"
        return 1
    fi

    return 0
}

# Output to file if specified
output_to_file() {
    local content="$1"

    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$content" > "$OUTPUT_FILE"
        chmod 600 "$OUTPUT_FILE"
        log_info "Output written to: $OUTPUT_FILE"
    else
        echo "$content"
    fi
}

# Main execution
main() {
    # Check Vault availability for most commands
    case "$COMMAND" in
        "health-check")
            # Health check will do its own availability check
            ;;
        *)
            if ! check_vault_availability; then
                exit 2
            fi
            ;;
    esac

    # Execute command
    case "$COMMAND" in
        "auth")
            vault_auth
            ;;
        "get-secret")
            if [[ ${#ARGS[@]} -ne 1 ]]; then
                log_error "get-secret requires exactly one argument: secret path"
                exit 10
            fi
            get_secret "${ARGS[0]}"
            ;;
        "set-secret")
            if [[ ${#ARGS[@]} -lt 2 ]]; then
                log_error "set-secret requires secret path and at least one KEY=VALUE pair"
                exit 10
            fi
            set_secret "${ARGS[0]}" "${ARGS[@]:1}"
            ;;
        "list-secrets")
            list_secrets "${ARGS[0]:-}"
            ;;
        "generate-env")
            if [[ ${#ARGS[@]} -ne 1 ]]; then
                log_error "generate-env requires exactly one argument: service name"
                exit 10
            fi
            generate_env_file "${ARGS[0]}"
            ;;
        "setup-approle")
            if [[ ${#ARGS[@]} -ne 1 ]]; then
                log_error "setup-approle requires exactly one argument: service name"
                exit 10
            fi
            setup_approle "${ARGS[0]}"
            ;;
        "health-check")
            health_check
            ;;
        "revoke-token")
            revoke_token
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            usage
            exit 10
            ;;
    esac
}

# Entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_args "$@"
    main
fi
