#!/bin/bash
# Webhook receiver script for automated deployments
# Place this on your dockermaster server and run with a webhook server like webhook or websocat

set -e

# Configuration
DEPLOY_PATH="/nfs/dockermaster/docker"
LOG_FILE="/var/log/docker-deploy.log"
WEBHOOK_TOKEN="${WEBHOOK_TOKEN:-}"

# Function to log messages
log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to validate webhook token
validate_token() {
  local provided_token="$1"
  if [ -z "$WEBHOOK_TOKEN" ]; then
    log_message "WARNING: No webhook token configured"
    return 0
  fi

  if [ "$provided_token" != "$WEBHOOK_TOKEN" ]; then
    log_message "ERROR: Invalid webhook token"
    return 1
  fi

  return 0
}

# Function to deploy a service
deploy_service() {
  local service="$1"

  log_message "Deploying service: $service"

  if [ ! -d "$DEPLOY_PATH/$service" ]; then
    log_message "ERROR: Service directory not found: $DEPLOY_PATH/$service"
    return 1
  fi

  cd "$DEPLOY_PATH/$service"

  # Pull latest images
  log_message "Pulling latest images for $service..."
  docker compose pull 2>&1 | tee -a "$LOG_FILE"

  # Deploy with rolling update
  log_message "Starting containers for $service..."
  docker compose up -d --remove-orphans 2>&1 | tee -a "$LOG_FILE"

  # Wait for containers to be healthy
  sleep 5

  # Check status
  log_message "Checking status for $service..."
  docker compose ps | tee -a "$LOG_FILE"

  log_message "Service $service deployed successfully"
  return 0
}

# Function to deploy all services
deploy_all_services() {
  log_message "Deploying all services..."

  for dir in "$DEPLOY_PATH"/*/; do
    if [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/docker-compose.yaml" ]; then
      service=$(basename "$dir")
      deploy_service "$service" || log_message "WARNING: Failed to deploy $service"
    fi
  done

  log_message "All services deployment completed"
}

# Main deployment logic
main() {
  local webhook_data="$1"
  local token="$2"

  # Validate token
  if ! validate_token "$token"; then
    exit 1
  fi

  # Parse webhook data (assuming JSON format)
  # You may need to install jq for JSON parsing
  if command -v jq &> /dev/null; then
    services=$(echo "$webhook_data" | jq -r '.services // "all"')
    repository=$(echo "$webhook_data" | jq -r '.repository // "unknown"')
    triggered_by=$(echo "$webhook_data" | jq -r '.triggered_by // "unknown"')
  else
    # Fallback if jq is not installed
    services="all"
    repository="unknown"
    triggered_by="webhook"
  fi

  log_message "Deployment triggered by: $triggered_by from repository: $repository"

  # Deploy services
  if [ "$services" = "all" ]; then
    deploy_all_services
  else
    # Deploy specific services (comma-separated)
    IFS=',' read -ra SERVICE_ARRAY <<< "$services"
    for service in "${SERVICE_ARRAY[@]}"; do
      service=$(echo "$service" | tr -d ' ')
      deploy_service "$service" || log_message "WARNING: Failed to deploy $service"
    done
  fi

  log_message "Deployment process completed"
}

# Check if running interactively or as webhook receiver
if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <webhook-data> [token]"
  echo "Or use with webhook server to receive POST requests"
  exit 1
fi

# Run main function
main "$@"
