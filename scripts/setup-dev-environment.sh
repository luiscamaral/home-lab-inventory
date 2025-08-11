#!/bin/bash
# Development Environment Setup Script
# Sets up the complete development environment for home-lab-inventory project

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
REQUIRED_TOOLS=(git docker node npm pre-commit)

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_step() {
    echo -e "\n${BOLD}${BLUE}📋 $1${NC}"
    echo "----------------------------------------"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check system requirements
check_requirements() {
    log_step "Checking System Requirements"
    
    local missing_tools=()
    
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if command_exists "$tool"; then
            local version=""
            case "$tool" in
                git) version=$(git --version | cut -d' ' -f3) ;;
                docker) version=$(docker --version | cut -d' ' -f3 | tr -d ',') ;;
                node) version=$(node --version) ;;
                npm) version=$(npm --version) ;;
                pre-commit) version=$(pre-commit --version | cut -d' ' -f2) ;;
            esac
            log_success "$tool is installed ($version)"
        else
            missing_tools+=("$tool")
            log_error "$tool is not installed"
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Installation instructions:"
        echo "------------------------"
        
        for tool in "${missing_tools[@]}"; do
            case "$tool" in
                git)
                    echo "📦 Git: https://git-scm.com/downloads"
                    echo "   macOS: brew install git"
                    echo "   Ubuntu: sudo apt install git"
                    ;;
                docker)
                    echo "🐳 Docker: https://docs.docker.com/get-docker/"
                    echo "   Make sure Docker daemon is running"
                    ;;
                node)
                    echo "📗 Node.js: https://nodejs.org/en/download/"
                    echo "   macOS: brew install node"
                    echo "   Ubuntu: curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -"
                    ;;
                npm)
                    echo "📦 NPM: Usually comes with Node.js"
                    ;;
                pre-commit)
                    echo "🔧 Pre-commit: pip install pre-commit"
                    echo "   macOS: brew install pre-commit"
                    echo "   Python: pip install pre-commit"
                    ;;
            esac
            echo ""
        done
        
        exit 1
    fi
    
    log_success "All required tools are installed!"
}

# Setup Git configuration if needed
setup_git() {
    log_step "Setting Up Git Configuration"
    
    if [ -z "$(git config --global user.name)" ]; then
        log_warning "Git user name not configured"
        read -p "Enter your full name for Git commits: " git_name
        git config --global user.name "$git_name"
        log_success "Git user name set to: $git_name"
    else
        log_success "Git user name: $(git config --global user.name)"
    fi
    
    if [ -z "$(git config --global user.email)" ]; then
        log_warning "Git user email not configured"
        read -p "Enter your email for Git commits: " git_email
        git config --global user.email "$git_email"
        log_success "Git user email set to: $git_email"
    else
        log_success "Git user email: $(git config --global user.email)"
    fi
    
    # Set up commit message template if not already set
    if [ -f "$PROJECT_ROOT/.gitmessage" ] && [ -z "$(git config --local commit.template)" ]; then
        git config --local commit.template .gitmessage
        log_success "Git commit template configured"
    fi
}

# Install Node.js dependencies
install_node_dependencies() {
    log_step "Installing Node.js Dependencies"
    
    cd "$PROJECT_ROOT"
    
    if [ -f "package.json" ]; then
        log_info "Installing npm packages..."
        npm install
        log_success "Node.js dependencies installed"
    else
        log_warning "No package.json found, skipping npm install"
    fi
}

# Setup pre-commit hooks
setup_pre_commit() {
    log_step "Setting Up Pre-commit Hooks"
    
    cd "$PROJECT_ROOT"
    
    if [ -f ".pre-commit-config.yaml" ]; then
        log_info "Installing pre-commit hooks..."
        pre-commit install --hook-type pre-commit
        pre-commit install --hook-type commit-msg
        
        log_info "Running initial pre-commit check..."
        if pre-commit run --all-files; then
            log_success "Pre-commit hooks installed and validated"
        else
            log_warning "Pre-commit found some issues, but installation completed"
            log_info "Run 'pre-commit run --all-files' to see and fix issues"
        fi
    else
        log_warning "No .pre-commit-config.yaml found, skipping pre-commit setup"
    fi
}

# Setup Husky if present
setup_husky() {
    log_step "Setting Up Husky Git Hooks"
    
    cd "$PROJECT_ROOT"
    
    if [ -f "package.json" ] && grep -q "husky" package.json; then
        log_info "Setting up Husky hooks..."
        
        if command_exists npx; then
            npx husky install
            log_success "Husky hooks installed"
        else
            log_warning "npx not available, skipping Husky setup"
        fi
    else
        log_info "Husky not configured in package.json, skipping"
    fi
}

# Validate Docker setup
validate_docker() {
    log_step "Validating Docker Setup"
    
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        log_info "Please start Docker and try again"
        exit 1
    fi
    
    log_success "Docker daemon is running"
    
    # Test Docker Compose functionality
    cd "$PROJECT_ROOT"
    
    # Find a sample docker-compose file to test
    local test_compose=""
    for compose_file in dockermaster/docker/compose/*/docker-compose.yml; do
        if [ -f "$compose_file" ]; then
            test_compose="$compose_file"
            break
        fi
    done
    
    if [ -n "$test_compose" ]; then
        log_info "Testing Docker Compose with: $test_compose"
        if docker compose -f "$test_compose" config --quiet; then
            log_success "Docker Compose validation passed"
        else
            log_warning "Docker Compose validation failed for $test_compose"
        fi
    else
        log_info "No Docker Compose files found to validate"
    fi
}

# Create useful development aliases and functions
setup_development_helpers() {
    log_step "Setting Up Development Helpers"
    
    local helpers_file="$PROJECT_ROOT/scripts/dev-helpers.sh"
    
    cat > "$helpers_file" << 'EOF'
#!/bin/bash
# Development helper functions and aliases
# Source this file in your shell: source scripts/dev-helpers.sh

# Project aliases
alias hli-lint='pre-commit run --all-files'
alias hli-test='make test'
alias hli-build='make build'
alias hli-clean='make clean'
alias hli-security='make security'

# Docker helpers
hli-docker-logs() {
    local service="${1:-}"
    if [ -z "$service" ]; then
        echo "Usage: hli-docker-logs <service-name>"
        echo "Available services:"
        find dockermaster/docker/compose -name "docker-compose.yml" -exec dirname {} \; | xargs -I {} basename {}
        return 1
    fi
    
    local compose_file="dockermaster/docker/compose/$service/docker-compose.yml"
    if [ -f "$compose_file" ]; then
        docker compose -f "$compose_file" logs -f
    else
        echo "Service not found: $service"
        return 1
    fi
}

hli-docker-status() {
    echo "Docker Services Status:"
    echo "======================"
    
    for dir in dockermaster/docker/compose/*/; do
        if [ -f "$dir/docker-compose.yml" ]; then
            service=$(basename "$dir")
            echo -n "$service: "
            cd "$dir"
            if docker compose ps --quiet | grep -q .; then
                echo "🟢 Running"
            else
                echo "🔴 Stopped"
            fi
            cd - >/dev/null
        fi
    done
}

# Git helpers
hli-git-clean() {
    echo "Cleaning up Git repository..."
    git fetch --prune
    git branch --merged | grep -v '\*\|main\|master' | xargs -n 1 git branch -d 2>/dev/null || true
    echo "Git cleanup completed"
}

hli-commit() {
    local type="${1:-}"
    local scope="${2:-}"
    local message="${3:-}"
    
    if [ -z "$type" ] || [ -z "$message" ]; then
        echo "Usage: hli-commit <type> [scope] <message>"
        echo ""
        echo "Types: feat, fix, docs, style, refactor, test, chore"
        echo "Scopes: servers, docker, security, docs, ci, deploy"
        echo ""
        echo "Example: hli-commit feat docker 'add new monitoring service'"
        echo "Example: hli-commit fix 'resolve port conflict in nginx'"
        return 1
    fi
    
    if [ -n "$scope" ] && [ "$scope" != "$message" ]; then
        git commit -m "$type($scope): $message"
    else
        git commit -m "$type: $message"
    fi
}

# Show this help
hli-help() {
    echo "🏠 Home Lab Inventory - Development Helpers"
    echo "==========================================="
    echo ""
    echo "Aliases:"
    echo "  hli-lint      - Run all linting checks"
    echo "  hli-test      - Run tests"
    echo "  hli-build     - Build all Docker images"
    echo "  hli-clean     - Clean build artifacts"
    echo "  hli-security  - Run security scans"
    echo ""
    echo "Functions:"
    echo "  hli-docker-logs <service>   - Show logs for a service"
    echo "  hli-docker-status           - Show status of all services"
    echo "  hli-git-clean              - Clean up Git branches"
    echo "  hli-commit <type> [scope] <message> - Make a conventional commit"
    echo "  hli-help                   - Show this help"
    echo ""
    echo "To load these helpers, run:"
    echo "  source scripts/dev-helpers.sh"
}

echo "🏠 Home Lab Inventory development helpers loaded!"
echo "Run 'hli-help' to see available commands."
EOF
    
    chmod +x "$helpers_file"
    log_success "Development helpers created at: $helpers_file"
    log_info "To load helpers: source scripts/dev-helpers.sh"
}

# Create development documentation
create_dev_docs() {
    log_step "Creating Development Documentation"
    
    local readme_dev="$PROJECT_ROOT/README-DEVELOPMENT.md"
    
    cat > "$readme_dev" << 'EOF'
# Development Guide

This guide helps you set up and work with the home-lab-inventory project.

## Quick Start

1. **Run the setup script:**
   ```bash
   ./scripts/setup-dev-environment.sh
   ```

2. **Load development helpers:**
   ```bash
   source scripts/dev-helpers.sh
   ```

3. **Make your first contribution:**
   ```bash
   # Create a new branch
   git checkout -b feature/your-feature-name
   
   # Make changes...
   
   # Commit with conventional format
   hli-commit feat "add new monitoring dashboard"
   
   # Push and create PR
   git push -u origin feature/your-feature-name
   ```

## Development Workflow

### Before Making Changes

- Run `hli-lint` to check code quality
- Run `hli-security` to check for security issues
- Check service status with `hli-docker-status`

### Making Changes

1. Create a feature branch from `main`
2. Make your changes following the coding standards
3. Write/update tests as needed
4. Update documentation if needed
5. Run pre-commit hooks automatically validate your changes

### Committing Changes

Use conventional commit format:
- `feat(scope): description` - New features
- `fix(scope): description` - Bug fixes  
- `docs(scope): description` - Documentation changes
- `chore(scope): description` - Maintenance tasks

Example: `feat(docker): add monitoring stack configuration`

### Testing

- **Lint everything:** `make lint` or `hli-lint`
- **Security scan:** `make security` or `hli-security`
- **Docker validation:** `make validate-docker`
- **Full test suite:** `make test` or `hli-test`

### Docker Services

- **View logs:** `hli-docker-logs <service-name>`
- **Check status:** `hli-docker-status`
- **Available services:** Check `dockermaster/docker/compose/` directories

## Project Structure

```
home-lab-inventory/
├── .github/workflows/     # CI/CD workflows
├── deployment/           # Deployment scripts and configs
├── dockermaster/         # Docker Master server configs
│   └── docker/compose/   # Docker Compose services
├── inventory/           # Infrastructure documentation
├── scripts/             # Development and utility scripts
└── docs/               # Project documentation
```

## Useful Commands

| Command | Description |
|---------|-------------|
| `hli-help` | Show all available helpers |
| `hli-lint` | Run all linting checks |
| `hli-security` | Run security scans |
| `hli-docker-status` | Show service status |
| `hli-git-clean` | Clean up merged branches |
| `make help` | Show Makefile targets |

## Troubleshooting

### Pre-commit Issues
```bash
# Reinstall hooks
pre-commit uninstall
pre-commit install

# Run specific hook
pre-commit run --all-files <hook-name>
```

### Docker Issues
```bash
# Check Docker daemon
docker info

# Validate compose files
docker compose -f <file> config
```

### Git Issues
```bash
# Reset pre-commit
pre-commit clean
pre-commit install

# Clean up repository
hli-git-clean
```

## Contributing

1. Read [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines
2. Follow the coding standards and commit conventions
3. Ensure all tests and checks pass before submitting PR
4. Update documentation as needed

## Getting Help

- Check the [Makefile](Makefile) for available commands
- Review [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines
- Look at existing code for examples
- Ask questions in pull request discussions

Happy coding! 🏠🐳
EOF
    
    log_success "Development documentation created: $readme_dev"
}

# Main setup function
main() {
    echo -e "${BOLD}${BLUE}"
    cat << 'EOF'
    ┌─────────────────────────────────────────────────────────────┐
    │                                                             │
    │  🏠 Home Lab Inventory - Development Environment Setup     │
    │                                                             │
    │  This script will configure your development environment    │
    │  with all necessary tools and configurations.               │
    │                                                             │
    └─────────────────────────────────────────────────────────────┘
EOF
    echo -e "${NC}"
    
    log_info "Starting development environment setup..."
    log_info "Project root: $PROJECT_ROOT"
    
    # Check if we're in the right directory
    if [ ! -f "$PROJECT_ROOT/.pre-commit-config.yaml" ]; then
        log_error "This doesn't appear to be the home-lab-inventory project root"
        log_error "Please run this script from the project root directory"
        exit 1
    fi
    
    # Run setup steps
    check_requirements
    setup_git
    install_node_dependencies
    setup_pre_commit
    setup_husky
    validate_docker
    setup_development_helpers
    create_dev_docs
    
    # Final summary
    echo ""
    echo -e "${BOLD}${GREEN}🎉 Development Environment Setup Complete!${NC}"
    echo ""
    echo "Next steps:"
    echo "----------"
    echo "1. Load development helpers:"
    echo -e "   ${BLUE}source scripts/dev-helpers.sh${NC}"
    echo ""
    echo "2. Check everything works:"
    echo -e "   ${BLUE}hli-lint${NC}"
    echo ""
    echo "3. Read the development guide:"
    echo -e "   ${BLUE}cat README-DEVELOPMENT.md${NC}"
    echo ""
    echo "4. Start developing:"
    echo -e "   ${BLUE}git checkout -b feature/your-feature${NC}"
    echo ""
    log_success "Happy coding! 🚀"
}

# Run main function
main "$@"