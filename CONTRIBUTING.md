# Contributing to Home Lab Inventory

Welcome to the Home Lab Inventory project! This guide provides everything you need to know to contribute effectively to our infrastructure documentation and automation systems.

## 📋 Table of Contents

- [Quick Start](#quick-start)
- [Development Environment Setup](#development-environment-setup)
- [Development Workflow](#development-workflow)
- [Code Quality Standards](#code-quality-standards)
- [Infrastructure Guidelines](#infrastructure-guidelines)
- [Testing Requirements](#testing-requirements)
- [Commit Message Conventions](#commit-message-conventions)
- [Pull Request Process](#pull-request-process)
- [Security Guidelines](#security-guidelines)
- [Common Tasks](#common-tasks)
- [Troubleshooting](#troubleshooting)
- [Getting Help](#getting-help)

## 🚀 Quick Start

### Prerequisites

Before contributing, ensure you have the following installed:

- **Node.js** >= 18.0 (with npm >= 9.0)
- **Python** >= 3.8
- **Docker** and **Docker Compose**
- **Git**

### First-Time Setup

1. **Fork and Clone**
   ```bash
   # Fork the repository on GitHub, then:
   git clone https://github.com/YOUR-USERNAME/home-lab-inventory.git
   cd home-lab-inventory
   ```

2. **Setup Development Environment**
   ```bash
   # One-command setup for everything
   make setup
   ```

3. **Verify Setup**
   ```bash
   # Run all validations to ensure everything works
   make test
   ```

4. **Start Contributing**
   ```bash
   # Check available commands
   make help
   ```

## 🛠️ Development Environment Setup

### Automated Setup

The quickest way to get started is using our automated setup:

```bash
make setup
```

This command will:

- ✅ Check all prerequisites
- ✅ Install Node.js dependencies
- ✅ Install Python linting tools
- ✅ Setup pre-commit hooks
- ✅ Configure git commit templates
- ✅ Install additional linting tools

### Manual Setup (Alternative)

If you prefer to set up manually:

```bash
# Install Node.js dependencies
npm install

# Install Python tools
pip3 install --user pre-commit commitizen yamllint bandit safety

# Install pre-commit hooks
pre-commit install

# Setup git commit template
git config commit.template .gitmessage

# Install additional tools
npm install -g markdownlint-cli
```

### Development Tools

Our project uses several tools to maintain code quality:

| Tool | Purpose | Config File |
|------|---------|------------|
| **Pre-commit** | Git hook automation | `.pre-commit-config.yaml` |
| **Commitlint** | Commit message validation | `.commitlintrc.json` |
| **Yamllint** | YAML file linting | `.yamllint.yml` |
| **Markdownlint** | Markdown standardization | `.markdownlint.json` |
| **Hadolint** | Dockerfile best practices | Pre-commit config |
| **Shellcheck** | Shell script validation | Pre-commit config |
| **Gitleaks** | Secret detection | `.gitleaks.toml` |

## 🔄 Development Workflow

### 1. Branch Strategy

We use a feature branch workflow:

```bash
# Always start from the latest main
git checkout main
git pull origin main

# Create a feature branch
git checkout -b feature/your-feature-name
# or
git checkout -b fix/issue-description
# or
git checkout -b docs/documentation-update
```

### 2. Development Process

1. **Make Your Changes**
   ```bash
   # Edit files as needed
   # Add new inventory entries, update configurations, etc.
   ```

2. **Test Locally**
   ```bash
   # Run quick checks during development
   make quick-check
   
   # Run full validation before committing
   make test
   ```

3. **Commit Changes**
   ```bash
   # Use our interactive commit tool
   make commit
   
   # Or commit manually following conventional format
   git add .
   git commit -m "feat(inventory): add new docker container documentation"
   ```

4. **Push and Create PR**
   ```bash
   git push origin feature/your-feature-name
   # Then create a pull request on GitHub
   ```

### 3. Branch Naming Conventions

Use descriptive branch names with prefixes:

- `feature/` - New functionality or enhancements
- `fix/` - Bug fixes
- `docs/` - Documentation updates
- `chore/` - Maintenance tasks
- `security/` - Security-related changes

**Examples:**
- `feature/add-prometheus-monitoring`
- `fix/docker-compose-validation`
- `docs/update-server-inventory`
- `chore/update-dependencies`

## 📏 Code Quality Standards

### Automated Quality Checks

All code must pass our automated quality checks:

```bash
# Run all linting
make lint

# Individual linters
make lint-yaml      # YAML files
make lint-markdown  # Markdown files
make lint-shell     # Shell scripts
make lint-docker    # Dockerfiles
make lint-json      # JSON files
make lint-actions   # GitHub workflows
```

### File Formatting Standards

- **YAML Files**: 2-space indentation, no trailing spaces
- **Markdown**: Follow markdownlint rules, use meaningful headings
- **JSON**: Properly formatted with 2-space indentation
- **Shell Scripts**: Use shellcheck-compliant syntax
- **Dockerfiles**: Follow hadolint best practices

### Pre-commit Hooks

Pre-commit hooks run automatically on `git commit`:

- File cleanup (trailing whitespace, EOF fixes)
- Syntax validation (JSON, YAML)
- Linting (Markdown, YAML, Dockerfiles, Shell)
- Security scanning (secrets detection)
- Docker Compose validation

**Bypass hooks only in emergencies:**
```bash
git commit -m "emergency fix" --no-verify
```

## 🏗️ Infrastructure Guidelines

### Docker Services

When adding or modifying Docker services:

1. **Service Documentation**
   ```markdown
   # Add to inventory/docker-containers.md
   ## Service Name
   - **Purpose**: What this service does
   - **Access**: How to access (URL, ports)
   - **Dependencies**: Required services
   - **Configuration**: Key config files
   ```

2. **Docker Compose Standards**
   ```yaml
   # Use consistent formatting
   version: '3.8'
   
   services:
     service-name:
       image: image:tag
       container_name: service-name
       restart: unless-stopped
       environment:
         - ENV_VAR=value
       volumes:
         - ./config:/config
       ports:
         - "8080:8080"
       networks:
         - proxy-network
   
   networks:
     proxy-network:
       external: true
   ```

3. **Dockerfile Best Practices**
   ```dockerfile
   # Use specific tags, not 'latest'
   FROM ubuntu:22.04
   
   # Combine RUN commands
   RUN apt-get update && \
       apt-get install -y package && \
       apt-get clean && \
       rm -rf /var/lib/apt/lists/*
   
   # Use non-root user
   USER 1000:1000
   ```

4. **Testing Docker Changes**
   ```bash
   # Validate configurations
   make test-docker-configs
   
   # Build changed containers
   make build-changed
   
   # Full build (if needed)
   make build-all
   ```

### Server Documentation

When updating server information:

1. **Server Inventory** (`inventory/servers.md`)
   - Physical specifications
   - Network configuration
   - Installed software
   - Access methods

2. **VM Documentation** (`inventory/virtual-machines.md`)
   - Host server
   - Resource allocation
   - Purpose and services
   - Network settings

3. **Commands Documentation** (`inventory/commands-available.md`)
   - Available tools and versions
   - Server-specific commands
   - Configuration locations

### Network Configuration

- Document IP addresses and VLANs
- Include firewall rules
- Note DNS configurations
- Record service dependencies

## 🧪 Testing Requirements

### Required Tests

All contributions must pass:

1. **Validation Tests**
   ```bash
   make validate          # Pre-commit hooks and structure
   make validate-commits  # Commit message format
   ```

2. **Linting Tests**
   ```bash
   make lint             # All linting checks
   ```

3. **Docker Tests**
   ```bash
   make test-docker-configs  # Docker Compose validation
   make build-changed        # Build affected containers
   ```

4. **Security Tests**
   ```bash
   make security         # Vulnerability and secret scans
   ```

### Local Testing Workflow

```bash
# During development
make quick-check      # Fast validation

# Before committing
make test            # Full test suite

# Before pushing
make pre-push        # Complete pre-push validation
```

### CI/CD Testing

Our GitHub Actions automatically run:

- ✅ Comprehensive linting (parallel execution)
- ✅ Pre-commit hook validation
- ✅ Commit message validation
- ✅ Docker build validation
- ✅ Documentation completeness
- ✅ File structure validation
- ✅ Security scanning

## 📝 Commit Message Conventions

We follow [Conventional Commits](https://conventionalcommits.org/). See [`COMMIT_CONVENTIONS.md`](COMMIT_CONVENTIONS.md) for detailed guidelines.

### Quick Reference

**Format:** `type(scope): description`

**Types:**
- `feat` - New features
- `fix` - Bug fixes
- `docs` - Documentation changes
- `style` - Formatting changes
- `refactor` - Code restructuring
- `test` - Testing improvements
- `chore` - Maintenance tasks
- `security` - Security improvements

**Examples:**
```
feat(inventory): add monitoring stack documentation
fix(docker): correct nginx proxy configuration
docs(readme): update setup instructions
security(compose): update base images to latest secure versions
```

### Interactive Commits

Use our interactive commit tool:

```bash
make commit
```

This guides you through:
1. Selecting commit type
2. Choosing scope
3. Writing description
4. Adding body (optional)
5. Noting breaking changes

## 🔄 Pull Request Process

### Before Creating a PR

1. **Run Full Validation**
   ```bash
   make test
   ```

2. **Check Commit Messages**
   ```bash
   make validate-commits
   ```

3. **Update Documentation**
   - Update relevant inventory files
   - Add configuration examples
   - Include access instructions

### PR Requirements

Your PR must include:

- ✅ **Clear description** of changes
- ✅ **Updated documentation** for any infrastructure changes
- ✅ **All tests passing** (automated CI checks)
- ✅ **Conventional commit messages**
- ✅ **No security vulnerabilities**
- ✅ **Docker configurations validated**

### PR Template

When creating a PR, include:

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Infrastructure change
- [ ] Security improvement

## Infrastructure Impact
- [ ] New services added
- [ ] Existing services modified
- [ ] Network changes
- [ ] Security implications

## Testing
- [ ] `make test` passes locally
- [ ] Docker builds successful
- [ ] Documentation updated

## Checklist
- [ ] Code follows project standards
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] No sensitive information included
```

### Review Process

1. **Automated Validation** - CI checks must pass
2. **Code Review** - Project maintainers review changes
3. **Infrastructure Review** - For infrastructure changes
4. **Security Review** - For security-sensitive changes
5. **Final Approval** - Maintainer approval required

### After PR Approval

```bash
# Rebase if requested
git rebase -i main

# Squash commits if needed
git reset --soft HEAD~n
git commit

# Update PR
git push --force-with-lease
```

## 🔒 Security Guidelines

### Secrets Management

**Never commit secrets!** Our security measures include:

- ✅ Gitleaks scanning in pre-commit hooks
- ✅ GitHub Actions secret scanning
- ✅ `.gitignore` for sensitive files

**Handle secrets properly:**

```bash
# Use environment files (not committed)
cp .env.example .env
# Edit .env with real values

# Reference in docker-compose.yml
env_file:
  - .env
```

### Sensitive Information

**Do NOT commit:**
- Passwords, API keys, tokens
- Private IP addresses (document in separate secure location)
- SSL certificates or private keys
- Personal information

**DO commit:**
- Example configurations
- Public documentation
- Network topology (without sensitive details)
- Service descriptions

### Security Scanning

Run security scans regularly:

```bash
# Full security suite
make security

# Individual scans
make security-scan    # Vulnerability scanning
make security-audit   # Dependency audit
make security-secrets # Secret detection
```

### Infrastructure Security

- Use strong, unique passwords
- Enable 2FA where possible
- Keep services updated
- Use network segmentation
- Implement proper firewall rules
- Regular backup verification

## 📋 Common Tasks

### Adding a New Docker Service

1. **Create service directory**
   ```bash
   mkdir -p dockermaster/docker/compose/new-service
   cd dockermaster/docker/compose/new-service
   ```

2. **Create docker-compose.yml**
   ```yaml
   version: '3.8'
   services:
     new-service:
       # Service configuration
   ```

3. **Test configuration**
   ```bash
   make test-docker-configs
   ```

4. **Update documentation**
   ```bash
   # Edit inventory/docker-containers.md
   # Add service details, access info, etc.
   ```

5. **Commit changes**
   ```bash
   make commit
   ```

### Updating Server Documentation

1. **Edit inventory files**
   ```bash
   # inventory/servers.md - Physical servers
   # inventory/virtual-machines.md - VMs
   # inventory/commands-available.md - Available tools
   ```

2. **Validate changes**
   ```bash
   make lint-markdown
   ```

3. **Update related documentation**
   ```bash
   # Update network diagrams
   # Update access procedures
   ```

### Adding GitHub Workflows

1. **Create workflow file**
   ```bash
   touch .github/workflows/new-workflow.yml
   ```

2. **Validate workflow**
   ```bash
   make lint-actions
   ```

3. **Test locally if possible**
   ```bash
   # Use act or similar tools for local testing
   ```

### Updating Dependencies

1. **Update package files**
   ```bash
   # package.json for Node.js deps
   # pyproject.toml for Python deps
   # Docker base images
   ```

2. **Test changes**
   ```bash
   make test
   ```

3. **Check security**
   ```bash
   make security-audit
   ```

## 🔧 Troubleshooting

### Common Issues

#### Pre-commit Hooks Failing

```bash
# Check what's failing
pre-commit run --all-files

# Fix individual issues
make lint-yaml
make lint-markdown
make format

# Update hooks if needed
pre-commit autoupdate
```

#### Docker Build Failures

```bash
# Check specific container
cd dockermaster/docker/compose/service-name
docker compose build

# Check logs
docker compose logs service-name

# Validate configuration
docker compose config
```

#### Commit Message Validation

```bash
# Check recent commits
make validate-commits

# Fix last commit message
git commit --amend

# Interactive rebase for multiple commits
git rebase -i HEAD~n
```

#### Node.js/npm Issues

```bash
# Clear caches
npm cache clean --force
rm -rf node_modules
npm install

# Check Node.js version
node --version  # Should be >= 18
```

#### Python Tool Issues

```bash
# Reinstall Python tools
pip3 install --user --upgrade pre-commit yamllint bandit

# Check Python version
python3 --version  # Should be >= 3.8
```

### Getting Unstuck

1. **Clean everything**
   ```bash
   make clean
   make setup
   ```

2. **Reset to known good state**
   ```bash
   git stash
   git checkout main
   git pull origin main
   ```

3. **Check tool versions**
   ```bash
   make status
   ```

4. **Run minimal validation**
   ```bash
   make quick-check
   ```

### Performance Issues

#### Slow Linting

```bash
# Run individual linters to isolate
make lint-yaml
make lint-markdown
make lint-shell

# Check file sizes
find . -name "*.md" -size +1M
```

#### Large Repository

```bash
# Check repository size
du -sh .git

# Clean up git history if needed
git gc --aggressive
```

## 🆘 Getting Help

### Documentation Resources

- **Project README**: [`README.md`](README.md)
- **Commit Guidelines**: [`COMMIT_CONVENTIONS.md`](COMMIT_CONVENTIONS.md)
- **Claude Configuration**: [`CLAUDE.md`](CLAUDE.md)
- **Makefile Help**: `make help`

### Quick Help Commands

```bash
# Show all available commands
make help

# Show development environment status
make status

# Show version information
make version

# Validate current setup
make test
```

### Community Support

1. **GitHub Issues** - Report bugs or request features
2. **Discussions** - Ask questions and share ideas
3. **Pull Request Reviews** - Get feedback on contributions

### Self-Diagnosis

```bash
# Check prerequisites
make check-prerequisites

# Validate environment
make status

# Run comprehensive test
make test

# Check security posture
make security
```

## 📊 Project Statistics

Run these commands to understand the project:

```bash
# Repository overview
make status

# Security status
make security

# Code quality status
make lint

# Infrastructure status
docker ps  # If Docker is running
```

## 🎯 Best Practices Summary

### Do's ✅

- Use `make` commands for all operations
- Follow conventional commit messages
- Update documentation with changes
- Test locally before pushing
- Use descriptive branch names
- Keep commits atomic and focused
- Run security scans regularly
- Document infrastructure changes thoroughly

### Don'ts ❌

- Don't commit secrets or sensitive data
- Don't bypass pre-commit hooks without reason
- Don't use generic commit messages
- Don't push untested changes
- Don't ignore security warnings
- Don't modify files without understanding impact
- Don't create overly large commits
- Don't forget to update documentation

## 🏆 Recognition

Contributors who follow these guidelines help maintain:

- 🔒 **Security** - Protecting infrastructure and data
- 📈 **Quality** - Maintaining high code standards
- 📚 **Documentation** - Keeping knowledge accessible
- 🚀 **Efficiency** - Streamlining development workflow
- 🤝 **Collaboration** - Enabling effective teamwork

Thank you for contributing to Home Lab Inventory! Your efforts help maintain and improve our infrastructure documentation and automation systems.

---

**Last Updated**: $(date)
**Version**: 1.0.0
**Maintainer**: Home Lab Team

For questions about this guide, please create an issue or reach out to the maintainers.