#!/bin/bash

# GitHub Runner Setup Script
# This script helps register and configure the GitHub Actions runner

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
ENV_EXAMPLE="$SCRIPT_DIR/.env.example"

# Functions
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

check_prerequisites() {
  log_info "Checking prerequisites..."

  # Check Docker
  if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed"
    exit 1
  fi
  log_success "Docker is installed"

  # Check Docker Compose
  if ! docker compose version &> /dev/null; then
    log_error "Docker Compose is not installed"
    exit 1
  fi
  log_success "Docker Compose is installed"

  # Check Docker daemon
  if ! docker info &> /dev/null; then
    log_error "Docker daemon is not running"
    exit 1
  fi
  log_success "Docker daemon is running"
}

setup_environment() {
  log_info "Setting up environment..."

  # Check if .env exists
  if [[ -f "$ENV_FILE" ]]; then
    log_warning ".env file already exists"
    read -p "Do you want to reconfigure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log_info "Keeping existing configuration"
      return
    fi
  fi

  # Copy template
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  log_info "Created .env file from template"

  # Get GitHub token
  echo
  log_info "GitHub Personal Access Token Setup"
  echo "To create a token:"
  echo "1. Go to: https://github.com/settings/tokens/new"
  echo "2. Select 'repo' scope for repository runners"
  echo "3. For organization runners, also select 'admin:org'"
  echo
  read -sp "Enter your GitHub Personal Access Token: " github_token
  echo

  if [[ -z "$github_token" ]]; then
    log_error "GitHub token is required"
    exit 1
  fi

  # Update .env file
  sed -i.bak "s|your_github_personal_access_token_here|$github_token|" "$ENV_FILE"
  rm -f "$ENV_FILE.bak"

  # Ask for runner name
  read -p "Enter runner name (default: dockermaster-runner): " runner_name
  runner_name=${runner_name:-dockermaster-runner}
  sed -i.bak "s|RUNNER_NAME=.*|RUNNER_NAME=$runner_name|" "$ENV_FILE"
  rm -f "$ENV_FILE.bak"

  # Ask for labels
  read -p "Enter additional labels (comma-separated, press Enter for defaults): " labels
  if [[ ! -z "$labels" ]]; then
    default_labels="self-hosted,linux,x64,dockermaster,docker"
    sed -i.bak "s|LABELS=.*|LABELS=$default_labels,$labels|" "$ENV_FILE"
    rm -f "$ENV_FILE.bak"
  fi

  log_success "Environment configuration complete"
}

create_directories() {
  log_info "Creating necessary directories..."

  mkdir -p "$SCRIPT_DIR/work"
  mkdir -p "$SCRIPT_DIR/cache"
  mkdir -p "$SCRIPT_DIR/config"

  log_success "Directories created"
}

start_runner() {
  log_info "Starting GitHub runner..."

  cd "$SCRIPT_DIR"

  # Pull latest image
  docker compose pull

  # Start runner
  docker compose up -d

  # Wait for runner to start
  log_info "Waiting for runner to initialize..."
  sleep 10

  # Check if runner is running
  if docker compose ps | grep -q "running"; then
    log_success "Runner container started successfully"
  else
    log_error "Runner failed to start"
    echo "Check logs with: docker compose logs runner"
    exit 1
  fi
}

verify_registration() {
  log_info "Verifying runner registration..."

  # Check container logs for registration
  if docker compose logs runner 2>&1 | grep -q "Runner successfully added"; then
    log_success "Runner registered successfully"
  elif docker compose logs runner 2>&1 | grep -q "Http response code: Unauthorized"; then
    log_error "Authentication failed - check your GitHub token"
    exit 1
  else
    log_warning "Registration status unclear - check GitHub repository settings"
    echo "Visit: https://github.com/luiscamaral/home-lab-inventory/settings/actions/runners"
  fi

  # Show runner status
  echo
  log_info "Runner Status:"
  docker compose ps

  echo
  log_info "Recent logs:"
  docker compose logs --tail 20 runner
}

cleanup_on_error() {
  log_error "Setup failed - cleaning up..."
  docker compose down 2> /dev/null || true
  exit 1
}

# Main execution
main() {
  echo "============================================"
  echo "GitHub Actions Runner Setup for Dockermaster"
  echo "============================================"
  echo

  # Set trap for cleanup on error
  trap cleanup_on_error ERR

  # Run setup steps
  check_prerequisites
  setup_environment
  create_directories
  start_runner
  verify_registration

  echo
  echo "============================================"
  log_success "GitHub runner setup complete!"
  echo "============================================"
  echo
  echo "Next steps:"
  echo "1. Verify runner at: https://github.com/luiscamaral/home-lab-inventory/settings/actions/runners"
  echo "2. Update workflows to use: runs-on: [self-hosted, dockermaster]"
  echo "3. Monitor runner with: docker compose logs -f runner"
  echo
  echo "To stop the runner: docker compose down"
  echo "To restart runner: docker compose restart"
}

# Run main function
main "$@"
