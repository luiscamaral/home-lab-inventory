#!/bin/bash
# GitHub Sync Script - Pull-based deployment for servers behind NAT/firewall
# Run this script via cron to periodically check for updates

set -e

# Configuration
DEPLOY_PATH="/nfs/dockermaster/docker"
GITHUB_REPO="luiscamaral/home-lab-inventory"
GITHUB_API="https://api.github.com"
STATE_FILE="/var/lib/docker-deploy/last-deployment.state"
LOG_FILE="/var/log/docker-deploy.log"

# Create state directory if it doesn't exist
mkdir -p "$(dirname "$STATE_FILE")"

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to get latest commit SHA from GitHub
get_latest_commit() {
    local branch="${1:-main}"
    curl -s "${GITHUB_API}/repos/${GITHUB_REPO}/commits/${branch}" | \
        grep '"sha"' | head -1 | cut -d'"' -f4
}

# Function to check GitHub Container Registry for new images
check_for_new_images() {
    local service="$1"
    local current_digest="$2"
    
    # Get the current image digest from the registry
    # Note: This requires the image to be public or authentication to be configured
    local registry_image="ghcr.io/${GITHUB_REPO%/*}/${service}:latest"
    
    # Pull image metadata without downloading the image
    docker manifest inspect "$registry_image" 2>/dev/null | \
        grep -o '"digest": "[^"]*"' | head -1 | cut -d'"' -f4
}

# Function to get current running image digest
get_running_image_digest() {
    local service="$1"
    docker inspect --format='{{.Image}}' "$service" 2>/dev/null || echo "none"
}

# Function to deploy a service
deploy_service() {
    local service="$1"
    
    log_message "Checking service: $service"
    
    if [ ! -d "$DEPLOY_PATH/$service" ]; then
        log_message "Service directory not found: $DEPLOY_PATH/$service"
        return 1
    fi
    
    cd "$DEPLOY_PATH/$service"
    
    # Check if service uses GitHub Container Registry images
    if grep -q "ghcr.io" docker-compose.yml 2>/dev/null || \
       grep -q "ghcr.io" docker-compose.yaml 2>/dev/null; then
        
        # Pull latest images
        log_message "Pulling latest images for $service..."
        if docker compose pull 2>&1 | tee -a "$LOG_FILE"; then
            # Check if images were actually updated
            if docker compose pull 2>&1 | grep -q "Downloaded newer image"; then
                log_message "New images found for $service, deploying..."
                docker compose up -d --remove-orphans 2>&1 | tee -a "$LOG_FILE"
                log_message "Service $service updated successfully"
            else
                log_message "Service $service is up to date"
            fi
        else
            log_message "Failed to pull images for $service"
            return 1
        fi
    else
        log_message "Service $service does not use registry images, skipping"
    fi
    
    return 0
}

# Function to check and deploy all services
check_and_deploy_all() {
    log_message "Starting deployment check..."
    
    local updated_count=0
    
    for dir in "$DEPLOY_PATH"/*/; do
        if [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/docker-compose.yaml" ]; then
            service=$(basename "$dir")
            if deploy_service "$service"; then
                ((updated_count++)) || true
            fi
        fi
    done
    
    log_message "Deployment check completed. $updated_count services checked."
}

# Function to save state
save_state() {
    local commit_sha="$1"
    echo "$commit_sha" > "$STATE_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S')" >> "$STATE_FILE"
}

# Function to load state
load_state() {
    if [ -f "$STATE_FILE" ]; then
        head -1 "$STATE_FILE" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Main logic
main() {
    log_message "=== Starting GitHub sync check ==="
    
    # Get current commit from GitHub
    current_commit=$(get_latest_commit "main")
    if [ -z "$current_commit" ]; then
        log_message "ERROR: Could not fetch latest commit from GitHub"
        exit 1
    fi
    
    # Load last known commit
    last_commit=$(load_state)
    
    log_message "Current commit: $current_commit"
    log_message "Last deployed commit: ${last_commit:-none}"
    
    # Check if there are new changes
    if [ "$current_commit" != "$last_commit" ] || [ -z "$last_commit" ]; then
        log_message "New changes detected, checking for updates..."
        check_and_deploy_all
        save_state "$current_commit"
    else
        log_message "No new commits, checking for image updates anyway..."
        # Still check for image updates even if no new commits
        # (images might have been rebuilt/updated)
        check_and_deploy_all
    fi
    
    log_message "=== GitHub sync check completed ==="
}

# Run main function
main "$@"