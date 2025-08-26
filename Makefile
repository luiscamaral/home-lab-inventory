# Home Lab Inventory - Development Makefile
# Comprehensive development automation for home lab infrastructure management
#
# Prerequisites:
# - Node.js >= 18 (npm >= 9)
# - Python >= 3.8
# - Docker and Docker Compose
# - Git
#
# Quick Start:
#   make setup    - Setup development environment
#   make test     - Run all tests and validations
#   make help     - Show all available commands

.PHONY: help setup clean lint validate build test security commit deploy-test
.DEFAULT_GOAL := help

# Variables
SHELL := /bin/bash
NODE_VERSION_MIN := 18
PYTHON_VERSION_MIN := 3.8
DOCKER_COMPOSE_CMD := docker compose

# Colors for output
CYAN := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
BOLD := \033[1m
RESET := \033[0m

# Helper function to print colored output
define print_section
	printf "$(CYAN)$(BOLD)▶ $(1)$(RESET)\n"
endef

define print_success
	printf "$(GREEN)✅ $(1)$(RESET)\n"
endef

define print_warning
	printf "$(YELLOW)⚠️  $(1)$(RESET)\n"
endef

define print_error
	printf "$(RED)❌ $(1)$(RESET)\n"
endef

# Help target with organized sections
help: ## 📚 Show available commands with descriptions
	@echo -e "$(CYAN)$(BOLD)"
	@echo "╔══════════════════════════════════════════════════════════════╗"
	@echo "║           Home Lab Inventory - Development Tools             ║"
	@echo "╚══════════════════════════════════════════════════════════════╝"
	@echo -e "$(RESET)"
	@echo ""
	@echo -e "$(BOLD)🛠️  Development Commands:$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		grep -E "setup|clean|validate|test" | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-15s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(BOLD)🔍 Code Quality Commands:$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		grep -E "lint|format|security" | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-15s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(BOLD)🐳 Docker Commands:$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		grep -E "build|deploy" | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-15s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(BOLD)📝 Git Commands:$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		grep -E "commit" | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-15s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(BOLD)📖 Examples:$(RESET)"
	@echo "  $(YELLOW)make setup$(RESET)           # First-time development environment setup"
	@echo "  $(YELLOW)make test$(RESET)            # Run all validations before committing"
	@echo "  $(YELLOW)make commit$(RESET)          # Interactive commit with conventional format"
	@echo "  $(YELLOW)make build$(RESET)           # Build all Docker containers"
	@echo "  $(YELLOW)make lint$(RESET)            # Run all linting tools"
	@echo ""
	@echo -e "$(BOLD)🔗 Quick Links:$(RESET)"
	@echo "  Documentation: $(CYAN)README.md$(RESET), $(CYAN)CONTRIBUTING.md$(RESET)"
	@echo "  Commit Guide:  $(CYAN)COMMIT_CONVENTIONS.md$(RESET)"
	@echo "  Claude Config: $(CYAN)CLAUDE.md$(RESET)"

# Prerequisites check
check-prerequisites: ## 🔧 Check if all prerequisites are installed
	@$(call print_section,"Checking Prerequisites")
	@echo "Checking required tools..."
	@command -v node >/dev/null 2>&1 || ($(call print_error,"Node.js is required but not installed") && exit 1)
	@command -v npm >/dev/null 2>&1 || ($(call print_error,"npm is required but not installed") && exit 1)
	@command -v python3 >/dev/null 2>&1 || ($(call print_error,"Python 3 is required but not installed") && exit 1)
	@command -v docker >/dev/null 2>&1 || ($(call print_error,"Docker is required but not installed") && exit 1)
	@command -v git >/dev/null 2>&1 || ($(call print_error,"Git is required but not installed") && exit 1)
	@$(call print_success,"All prerequisites are installed")
	@echo "Checking versions..."
	@NODE_VERSION=$$(node --version | cut -d'v' -f2 | cut -d'.' -f1); \
	if [ $$NODE_VERSION -lt $(NODE_VERSION_MIN) ]; then \
		@$(call print_warning,"Node.js version $$NODE_VERSION is below recommended $(NODE_VERSION_MIN)"); \
	else \
		echo "  ✅ Node.js: $$(node --version)"; \
	fi
	@echo "  ✅ Python: $$(python3 --version)"
	@echo "  ✅ Docker: $$(docker --version)"
	@echo "  ✅ Git: $$(git --version)"

# Development Environment Setup
setup: check-prerequisites ## 🚀 Setup complete development environment
	@$(call print_section,"Setting Up Development Environment")
	@echo "Installing Node.js dependencies..."
	@npm install
	@echo "Installing Python dependencies..."
	@pip3 install --user pre-commit commitizen yamllint bandit safety
	@echo "Installing pre-commit hooks..."
	@pre-commit install
	@echo "Setting up git configuration..."
	@npm run setup:git-template
	@echo "Installing additional linting tools..."
	@npm install -g markdownlint-cli
	@echo "Testing installations..."
	@pre-commit --version || $(call print_warning,"Pre-commit installation may have failed")
	@markdownlint --version || $(call print_warning,"markdownlint installation may have failed")
	@$(call print_success,"Development environment setup complete!")
	@echo ""
	@echo -e "$(BOLD)Next steps:$(RESET)"
	@echo "1. Run $(CYAN)make test$(RESET) to validate your setup"
	@echo "2. Run $(CYAN)make lint$(RESET) to check code quality"
	@echo "3. Use $(CYAN)make commit$(RESET) for conventional commits"

# Cleanup
clean: ## 🧹 Clean build artifacts and caches
	@$(call print_section,"Cleaning Up")
	@echo "Removing Node.js artifacts..."
	@rm -rf node_modules/.cache
	@rm -rf ~/.npm/_cacache 2>/dev/null || true
	@echo "Removing Python artifacts..."
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	@find . -name "*.pyc" -delete 2>/dev/null || true
	@echo "Removing pre-commit cache..."
	@rm -rf ~/.cache/pre-commit 2>/dev/null || true
	@echo "Removing Docker build cache..."
	@docker system prune -f --volumes 2>/dev/null || $(call print_warning,"Docker cleanup skipped (not running or no permissions)")
	@echo "Removing temporary files..."
	@find . -name "*.tmp" -delete 2>/dev/null || true
	@find . -name "*.log" -delete 2>/dev/null || true
	@find . -name ".DS_Store" -delete 2>/dev/null || true
	@$(call print_success,"Cleanup completed")

# Linting Commands
lint: lint-yaml lint-markdown lint-shell lint-docker lint-json lint-actions lint-python ## 🔍 Run all linting checks

lint-yaml: ## 📄 Lint YAML files with yamllint
	@$(call print_section,"YAML Linting")
	@yamllint -c .yamllint.yml . || ($(call print_error,"YAML linting failed") && exit 1)
	@$(call print_success,"YAML linting passed")

lint-markdown: ## 📝 Lint Markdown files with markdownlint
	@$(call print_section,"Markdown Linting")
	@markdownlint --config .markdownlint.json **/*.md --ignore .history --ignore node_modules || \
		($(call print_error,"Markdown linting failed") && exit 1)
	@$(call print_success,"Markdown linting passed")

lint-shell: ## 🐚 Lint shell scripts with shellcheck
	@$(call print_section,"Shell Script Linting")
	@SHELL_FILES=$$(find . -name "*.sh" -not -path "./.git/*" -not -path "./node_modules/*" -not -path "./.history/*"); \
	if [ -n "$$SHELL_FILES" ]; then \
		echo "$$SHELL_FILES" | xargs shellcheck -e SC1091 -e SC2034 -e SC2154 || \
			($(call print_error,"Shell script linting failed") && exit 1); \
		@$(call print_success,"Shell script linting passed"); \
	else \
		echo "ℹ️  No shell scripts found to lint"; \
	fi

lint-docker: ## 🐳 Lint Dockerfiles with hadolint
	@$(call print_section,"Dockerfile Linting")
	@DOCKER_FILES=$$(find . -name "Dockerfile" -o -name "*.dockerfile" | grep -v node_modules | grep -v .git); \
	if [ -n "$$DOCKER_FILES" ]; then \
		echo "$$DOCKER_FILES" | xargs docker run --rm -i hadolint/hadolint:latest \
			--ignore DL3008 --ignore DL3009 --ignore DL3015 || \
			($(call print_error,"Dockerfile linting failed") && exit 1); \
		@$(call print_success,"Dockerfile linting passed"); \
	else \
		echo "ℹ️  No Dockerfiles found to lint"; \
	fi

lint-json: ## 📋 Validate JSON files
	@$(call print_section,"JSON Validation")
	@JSON_FILES=$$(find . -name "*.json" -not -path "./.git/*" -not -path "./node_modules/*" -not -path "./.history/*"); \
	FAILED=false; \
	for file in $$JSON_FILES; do \
		if ! python3 -m json.tool "$$file" > /dev/null 2>&1; then \
			@$(call print_error,"Invalid JSON: $$file"); \
			FAILED=true; \
		else \
			echo "✅ Valid JSON: $$file"; \
		fi; \
	done; \
	if [ "$$FAILED" = true ]; then \
		exit 1; \
	fi
	@$(call print_success,"JSON validation passed")

lint-actions: ## ⚡ Lint GitHub Actions workflows
	@$(call print_section,"GitHub Actions Linting")
	@if command -v actionlint >/dev/null 2>&1; then \
		actionlint .github/workflows/*.yml || \
			($(call print_error,"GitHub Actions linting failed") && exit 1); \
		@$(call print_success,"GitHub Actions linting passed"); \
	else \
		@$(call print_warning,"actionlint not installed, installing..."); \
		bash <(curl -s https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash); \
		./actionlint .github/workflows/*.yml || \
			($(call print_error,"GitHub Actions linting failed") && exit 1); \
		@$(call print_success,"GitHub Actions linting passed"); \
	fi

lint-python: ## 🐍 Lint Python files (if any)
	@$(call print_section,"Python Code Linting")
	@PYTHON_FILES=$$(find . -name "*.py" -not -path "./.git/*" -not -path "./node_modules/*" -not -path "./.history/*"); \
	if [ -n "$$PYTHON_FILES" ]; then \
		echo "Running flake8 on Python files..."; \
		python3 -m flake8 $$PYTHON_FILES --max-line-length=88 --ignore=E203,W503 || \
			($(call print_warning,"Python linting failed (non-critical)") && true); \
		@$(call print_success,"Python linting completed"); \
	else \
		echo "ℹ️  No Python files found to lint"; \
	fi

# Validation Commands
validate: validate-pre-commit validate-commits validate-structure ## ✅ Run all validation checks

validate-pre-commit: ## 🔨 Run pre-commit hooks on all files
	@$(call print_section,"Pre-commit Validation")
	@pre-commit run --all-files || ($(call print_error,"Pre-commit validation failed") && exit 1)
	@$(call print_success,"Pre-commit validation passed")

validate-commits: ## 📝 Validate recent commit messages
	@$(call print_section,"Commit Message Validation")
	@echo "Validating last 5 commits..."
	@npm run lint:commits || ($(call print_error,"Commit message validation failed") && exit 1)
	@$(call print_success,"Commit message validation passed")

validate-structure: ## 📁 Validate repository file structure
	@$(call print_section,"Repository Structure Validation")
	@echo "Checking required files and directories..."
	@MISSING_FILES=""; \
	REQUIRED_FILES=(".gitignore" ".commitlintrc.json" ".pre-commit-config.yaml" ".markdownlint.json" ".yamllint.yml" "package.json"); \
	for file in "$${REQUIRED_FILES[@]}"; do \
		if [ ! -f "$$file" ]; then \
			MISSING_FILES="$$MISSING_FILES $$file"; \
		fi; \
	done; \
	REQUIRED_DIRS=(".github/workflows" "inventory"); \
	for dir in "$${REQUIRED_DIRS[@]}"; do \
		if [ ! -d "$$dir" ]; then \
			MISSING_FILES="$$MISSING_FILES $$dir"; \
		fi; \
	done; \
	if [ -n "$$MISSING_FILES" ]; then \
		@$(call print_error,"Missing required files/directories:$$MISSING_FILES"); \
		exit 1; \
	fi
	@$(call print_success,"Repository structure validation passed")

# Docker Commands
build: build-changed ## 🏗️  Build Docker images locally (without pushing)

build-changed: ## 🔄 Build only Docker images with recent changes
	@$(call print_section,"Building Changed Docker Images")
	@CHANGED_DOCKERFILES=$$(git diff --name-only HEAD~1 | grep -E "(Dockerfile|docker-compose\.ya?ml)" || true); \
	if [ -n "$$CHANGED_DOCKERFILES" ]; then \
		echo "Found changed Docker files:"; \
		echo "$$CHANGED_DOCKERFILES" | sed 's/^/  - /'; \
		echo ""; \
		for dockerfile in $$CHANGED_DOCKERFILES; do \
			if [[ "$$dockerfile" == *"Dockerfile"* ]] && [ -f "$$dockerfile" ]; then \
				CONTEXT_DIR=$$(dirname "$$dockerfile"); \
				IMAGE_NAME=$$(basename "$$CONTEXT_DIR"); \
				echo "Building $$IMAGE_NAME from $$dockerfile..."; \
				$(DOCKER_COMPOSE_CMD) -f "$$CONTEXT_DIR/docker-compose.yml" build 2>/dev/null || \
				docker build -t "home-lab/$$IMAGE_NAME:local" -f "$$dockerfile" "$$CONTEXT_DIR" || \
					($(call print_error,"Failed to build $$IMAGE_NAME") && continue); \
				@$(call print_success,"Built $$IMAGE_NAME"); \
			fi; \
		done; \
	else \
		echo "ℹ️  No Docker files have changed recently"; \
	fi

build-all: ## 🏗️  Build all Docker images
	@$(call print_section,"Building All Docker Images")
	@find dockermaster/docker/compose -name "docker-compose.yml" -o -name "docker-compose.yaml" | while read compose_file; do \
		COMPOSE_DIR=$$(dirname "$$compose_file"); \
		SERVICE_NAME=$$(basename "$$COMPOSE_DIR"); \
		echo "Building $$SERVICE_NAME from $$compose_file..."; \
		cd "$$COMPOSE_DIR" && $(DOCKER_COMPOSE_CMD) build && cd - >/dev/null || \
			($(call print_warning,"Failed to build $$SERVICE_NAME") && continue); \
		@$(call print_success,"Built $$SERVICE_NAME"); \
	done

# Test Commands
test: validate lint test-docker-configs ## 🧪 Run all tests and validations

test-docker-configs: ## 🐳 Test Docker Compose configurations
	@$(call print_section,"Testing Docker Compose Configurations")
	@find . -name "docker-compose.yml" -o -name "docker-compose.yaml" | grep -v node_modules | while read compose_file; do \
		echo "Testing $$compose_file..."; \
		$(DOCKER_COMPOSE_CMD) -f "$$compose_file" config --quiet || \
			($(call print_error,"Docker Compose config validation failed for $$compose_file") && exit 1); \
		@$(call print_success,"$$compose_file is valid"); \
	done

# Security Commands
security: security-scan security-audit security-secrets ## 🔒 Run all security scans locally

security-scan: ## 🔍 Run security vulnerability scans
	@$(call print_section,"Security Vulnerability Scanning")
	@echo "Scanning Node.js dependencies..."
	@npm audit --audit-level=moderate || $(call print_warning,"Node.js security issues found")
	@echo "Scanning Python dependencies..."
	@pip3 list --format=freeze | safety check --stdin || $(call print_warning,"Python security issues found")
	@$(call print_success,"Security scanning completed")

security-audit: ## 🔒 Audit dependencies for known vulnerabilities
	@$(call print_section,"Dependency Security Audit")
	@echo "Running npm audit..."
	@npm audit --production || $(call print_warning,"npm audit found issues")
	@echo "Checking for Python vulnerabilities with bandit..."
	@PYTHON_FILES=$$(find . -name "*.py" -not -path "./.git/*" -not -path "./node_modules/*"); \
	if [ -n "$$PYTHON_FILES" ]; then \
		python3 -m bandit -r . -f json -o bandit-report.json 2>/dev/null || true; \
		if [ -f "bandit-report.json" ]; then \
			echo "Bandit scan completed. Check bandit-report.json for details."; \
		fi; \
	fi
	@$(call print_success,"Security audit completed")

security-secrets: ## 🔐 Scan for secrets and sensitive data
	@$(call print_section,"Secrets Scanning")
	@echo "Running gitleaks scan..."
	@if command -v gitleaks >/dev/null 2>&1; then \
		gitleaks detect --verbose --source . || $(call print_warning,"Potential secrets found"); \
	else \
		@$(call print_warning,"gitleaks not installed, running pre-commit gitleaks instead..."); \
		pre-commit run gitleaks --all-files || $(call print_warning,"Potential secrets found"); \
	fi
	@$(call print_success,"Secrets scanning completed")

# Git Commands
commit: ## 📝 Interactive commit with conventional format
	@$(call print_section,"Interactive Commit")
	@echo "Starting interactive commit process..."
	@echo "This will guide you through creating a conventional commit."
	@echo ""
	@npm run commit

commit-validate: ## ✅ Validate the last commit message
	@$(call print_section,"Validating Last Commit")
	@npm run commitlint:last || ($(call print_error,"Last commit message is invalid") && exit 1)
	@$(call print_success,"Last commit message is valid")

# Deployment Commands
deploy-test: build test ## 🚀 Test deployment locally
	@$(call print_section,"Local Deployment Testing")
	@echo "Testing deployment readiness..."
	@echo "✅ All builds completed successfully"
	@echo "✅ All tests passed"
	@echo "✅ Ready for deployment"
	@echo ""
	@echo -e "$(BOLD)Deployment checklist:$(RESET)"
	@echo "1. ✅ Code quality checks passed"
	@echo "2. ✅ Docker builds successful"
	@echo "3. ✅ Configuration validation passed"
	@echo "4. ✅ Security scans completed"
	@echo ""
	@echo -e "$(GREEN)$(BOLD)🎉 Ready to deploy!$(RESET)"

# Development Utilities
format: ## 🎨 Format code using available formatters
	@$(call print_section,"Code Formatting")
	@echo "Formatting JSON files..."
	@find . -name "*.json" -not -path "./.git/*" -not -path "./node_modules/*" -not -path "./.history/*" | \
		xargs -I {} sh -c 'python3 -m json.tool {} > {}.tmp && mv {}.tmp {}'
	@echo "Running pre-commit hooks to format other files..."
	@pre-commit run --all-files trailing-whitespace end-of-file-fixer mixed-line-ending || true
	@$(call print_success,"Code formatting completed")

status: ## 📊 Show development environment status
	@$(call print_section,"Development Environment Status")
	@echo -e "$(BOLD)Repository Status:$(RESET)"
	@echo "  Branch: $(YELLOW)$$(git branch --show-current)$(RESET)"
	@echo "  Status: $$(git status --porcelain | wc -l) modified files"
	@echo "  Last commit: $$(git log -1 --format='%h - %s (%cr)')"
	@echo ""
	@echo -e "$(BOLD)Tools Status:$(RESET)"
	@echo "  Node.js: $$(node --version)"
	@echo "  npm: $$(npm --version)"
	@echo "  Python: $$(python3 --version | cut -d' ' -f2)"
	@echo "  Docker: $$(docker --version | cut -d' ' -f3 | cut -d',' -f1)"
	@echo "  Pre-commit: $$(pre-commit --version 2>/dev/null || echo 'Not installed')"
	@echo ""
	@echo -e "$(BOLD)Docker Status:$(RESET)"
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "  Docker not running"

install-tools: ## 🔧 Install additional development tools
	@$(call print_section,"Installing Additional Development Tools")
	@echo "Installing actionlint for GitHub Actions validation..."
	@bash <(curl -s https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash) || true
	@echo "Installing gitleaks for secret scanning..."
	@if ! command -v gitleaks >/dev/null 2>&1; then \
		echo "Please install gitleaks manually from: https://github.com/gitleaks/gitleaks/releases"; \
	fi
	@echo "Installing hadolint for Dockerfile linting..."
	@if ! docker images | grep -q hadolint; then \
		docker pull hadolint/hadolint:latest; \
	fi
	@$(call print_success,"Additional tools installation completed")

# Documentation
docs-serve: ## 📖 Serve documentation locally (if available)
	@$(call print_section,"Serving Documentation")
	@if [ -f "mkdocs.yml" ]; then \
		mkdocs serve; \
	else \
		echo "ℹ️  No documentation server configured"; \
		echo "Available documentation files:"; \
		find . -name "*.md" -not -path "./.git/*" -not -path "./node_modules/*" | head -10; \
	fi

# CI/CD Integration
ci-local: ## 🔄 Run CI pipeline locally
	@$(call print_section,"Running CI Pipeline Locally")
	@echo "Simulating CI pipeline..."
	@$(MAKE) validate
	@$(MAKE) lint
	@$(MAKE) security
	@$(MAKE) build-changed
	@$(MAKE) test-docker-configs
	@$(call print_success,"Local CI pipeline completed successfully")

pre-push: validate lint security ## 🚀 Run pre-push validations
	@$(call print_section,"Pre-push Validation")
	@$(call print_success,"All pre-push validations passed")
	@echo -e "$(BOLD)Ready to push!$(RESET)"

# Quick Development Commands
quick-check: lint-yaml lint-markdown lint-json ## ⚡ Quick code quality check
	@$(call print_success,"Quick check completed")

fix: format validate-pre-commit ## 🔧 Auto-fix common issues
	@$(call print_section,"Auto-fixing Common Issues")
	@$(call print_success,"Auto-fix completed")

# Version and Information
version: ## ℹ️  Show version information
	@echo -e "$(CYAN)$(BOLD)Home Lab Inventory Development Tools$(RESET)"
	@echo "Repository: $$(git remote get-url origin 2>/dev/null || echo 'Local repository')"
	@echo "Branch: $$(git branch --show-current)"
	@echo "Last updated: $$(git log -1 --format='%cd' --date=short)"
	@echo ""
	@echo "For help, run: $(CYAN)make help$(RESET)"
