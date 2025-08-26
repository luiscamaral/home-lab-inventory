# Git Hooks for Home Lab Inventory

Comprehensive git hooks system providing local CI validation for the home-lab-inventory project. These hooks complement the existing GitHub Actions CI/CD pipeline by catching issues early in the development process.

## 🚀 Features

### Pre-commit Hook
- **YAML Validation**: Validates `.yml` and `.yaml` files including GitHub Actions workflows and Docker Compose files
- **Secret Detection**: Scans for hardcoded secrets, API keys, tokens, and sensitive data
- **File Validation**: Checks file types, sizes, and enforces repository policies
- **Code Quality**: Basic syntax checking for shell scripts, Python, and JSON files
- **Integration**: Works alongside existing pre-commit framework

### Commit-msg Hook
- **Conventional Commits**: Validates commit messages against conventional commits specification
- **Integration**: Seamlessly integrates with existing commitlint/Husky setup
- **Flexible**: Falls back to custom validation if commitlint is not available
- **Helpful**: Provides clear guidance when validation fails

### Pre-push Hook
- **Comprehensive Validation**: Runs all pre-commit checks plus additional validations
- **Commit History**: Validates all commit messages being pushed
- **Secret Scanning**: Deep scan of all changed files in pushed commits
- **Testing**: Optionally runs available test suites
- **Workflow Validation**: Comprehensive GitHub Actions workflow validation

## 📁 Directory Structure

```
.githooks/
├── hooks/
│   ├── pre-commit          # Pre-commit validation hook
│   ├── commit-msg          # Commit message validation hook
│   └── pre-push            # Pre-push comprehensive validation
├── utils/
│   ├── yaml-validator.py   # YAML syntax and workflow validation
│   ├── secret-detector.sh  # Secret and sensitive data detection
│   ├── conventional-commits.sh # Commit message format validation
│   └── file-checks.sh      # File type, size, and content validation
├── config/
│   ├── secret-patterns.txt # Patterns for secret detection
│   └── allowed-file-types.txt # File type and size configurations
├── setup.sh               # Installation and setup script
└── README.md              # This documentation
```

## 🛠️ Installation

### Quick Setup

```bash
# From repository root
cd /path/to/home-lab-inventory
.githooks/setup.sh
```

### Advanced Setup Options

```bash
# Force overwrite existing hooks
.githooks/setup.sh --force

# Quiet installation
.githooks/setup.sh --quiet

# Skip backing up existing hooks
.githooks/setup.sh --no-backup
```

### Manual Installation

If you prefer manual setup:

```bash
# Copy hooks to git hooks directory
cp .githooks/hooks/* .git/hooks/
chmod +x .git/hooks/*

# Verify installation
ls -la .git/hooks/pre-commit .git/hooks/commit-msg .git/hooks/pre-push
```

## 📋 Requirements

### Required
- **Git**: Version control system
- **Bash**: Shell for hook execution
- **Python 3**: For YAML validation and other utilities
- **PyYAML**: Python YAML library (`pip3 install PyYAML`)

### Recommended (for enhanced validation)
- **shellcheck**: Shell script linting
- **actionlint**: GitHub Actions workflow validation
- **hadolint**: Dockerfile linting
- **Docker**: Docker Compose validation

### Installation Commands

**macOS (Homebrew):**
```bash
brew install shellcheck actionlint hadolint
pip3 install PyYAML
```

**Ubuntu/Debian:**
```bash
sudo apt-get install shellcheck
pip3 install PyYAML
# actionlint and hadolint need manual installation
```

## 🎯 Usage

### Automatic Usage
Hooks run automatically during git operations:

```bash
git add .
git commit -m "feat(docker): add nginx container"  # Runs pre-commit and commit-msg hooks
git push origin feature-branch                     # Runs pre-push hook
```

### Manual Testing

Test individual utilities:

```bash
# Test YAML validation
.githooks/utils/yaml-validator.py .github/workflows/*.yml

# Test secret detection
.githooks/utils/secret-detector.sh --strict file1.txt file2.sh

# Test commit message validation
echo "feat: add new feature" | .githooks/utils/conventional-commits.sh -

# Test file validation
.githooks/utils/file-checks.sh --check-lines *.py *.sh
```

### Bypassing Hooks

Sometimes you may need to bypass hooks temporarily:

```bash
# Skip all hooks
git commit --no-verify -m "emergency fix"
git push --no-verify

# Skip only tests in pre-push
SKIP_TESTS=true git push origin main
```

## ⚙️ Configuration

### Secret Patterns

Edit `.githooks/config/secret-patterns.txt` to customize secret detection:

```
# Add custom patterns (NAME:REGEX format)
CUSTOM_API_KEY:api_key[\s]*=[\s]*[\'"][a-zA-Z0-9]{32,}[\'"]
CUSTOM_TOKEN:my_token[\s]*=[\s]*[\'"][a-zA-Z0-9]{20,}[\'"]
```

### File Types and Limits

Edit `.githooks/config/allowed-file-types.txt` to customize file validation:

```
# Extension:MaxSize(MB) format
.py:15
.js:10
.md:*
.custom:5

# Forbidden extensions (will be rejected)
REJECTED_EXTENSIONS=.exe,.bin,.secret

# Default size for unknown extensions
DEFAULT_MAX_SIZE=10
```

### Hook Behavior

Environment variables can modify hook behavior:

```bash
# Skip tests in pre-push hook
export SKIP_TESTS=true

# Make file checks strict
export STRICT_MODE=true

# Quiet mode for all hooks
export QUIET_MODE=true
```

## 🔧 Integration

### With Existing Pre-commit Framework

The hooks automatically detect and integrate with:
- **pre-commit framework**: Runs existing hooks alongside custom validation
- **commitlint**: Uses existing configuration for commit message validation
- **Husky**: Detects and respects existing Husky hooks

### With GitHub Actions

These local hooks complement the GitHub Actions workflows by:
- Catching issues before they reach the remote repository
- Reducing CI/CD pipeline failures
- Providing faster feedback during development

### With IDE Integration

Most IDEs can be configured to run git hooks:
- **VS Code**: Install git hooks extensions
- **IntelliJ**: Enable git hooks in VCS settings
- **Vim/Neovim**: Configure git integration plugins

## 🐛 Troubleshooting

### Common Issues

#### Hook Not Running
```bash
# Check if hooks are executable
ls -la .git/hooks/pre-commit .git/hooks/commit-msg .git/hooks/pre-push

# Make executable if needed
chmod +x .git/hooks/pre-commit .git/hooks/commit-msg .git/hooks/pre-push

# Check git hooks path
git config core.hooksPath
```

#### Permission Denied
```bash
# Fix permissions on all hook utilities
chmod +x .githooks/utils/*.sh .githooks/utils/*.py
```

#### Python YAML Module Missing
```bash
# Install PyYAML
pip3 install PyYAML

# Or use system package manager
brew install python-yq  # macOS
sudo apt-get install python3-yaml  # Ubuntu
```

#### False Positive Secret Detection
```bash
# Review and update secret patterns
nano .githooks/config/secret-patterns.txt

# Test specific file
.githooks/utils/secret-detector.sh --help
```

### Hook Debugging

Enable verbose output for debugging:

```bash
# Debug pre-commit hook
git add . && .git/hooks/pre-commit

# Debug with set -x for full tracing
sed -i.bak 's/set -euo pipefail/set -euxo pipefail/' .git/hooks/pre-commit
```

### Getting Help

Each utility provides help information:

```bash
.githooks/utils/yaml-validator.py --help
.githooks/utils/secret-detector.sh --help
.githooks/utils/conventional-commits.sh --help
.githooks/utils/file-checks.sh --help
```

## 📊 Performance

### Benchmarks (Approximate)

| Hook | Small Repo | Medium Repo | Large Repo |
|------|------------|-------------|------------|
| pre-commit | 2-5 sec | 5-10 sec | 10-20 sec |
| commit-msg | <1 sec | <1 sec | <1 sec |
| pre-push | 5-15 sec | 15-30 sec | 30-60 sec |

### Optimization Tips

1. **Skip Tests**: Use `SKIP_TESTS=true` for faster pre-push
2. **Exclude Large Files**: Update file type configuration
3. **Limit Secret Scanning**: Customize patterns for your use case
4. **Parallel Execution**: Hooks automatically use parallel processing where possible

## 🔄 Maintenance

### Updating Hooks

```bash
# Re-run setup to update hooks
.githooks/setup.sh --force

# Or manually copy updated hooks
cp .githooks/hooks/* .git/hooks/
chmod +x .git/hooks/*
```

### Updating Patterns

```bash
# Edit secret patterns
nano .githooks/config/secret-patterns.txt

# Edit file type configuration
nano .githooks/config/allowed-file-types.txt

# Test changes
.githooks/utils/secret-detector.sh --help
.githooks/utils/file-checks.sh --help
```

### Backup and Recovery

```bash
# Hooks are automatically backed up during setup
ls .git/hooks.backup.*

# Restore from backup if needed
cp .git/hooks.backup.YYYYMMDD_HHMMSS/* .git/hooks/
```

## 📚 Examples

### Commit Message Examples

✅ **Good:**
```
feat(docker): add nginx reverse proxy container
fix(security): resolve secret detection in workflows  
docs(inventory): update server documentation
ci(github): add self-hosted runner support
chore: update dependencies and cleanup code
```

❌ **Bad:**
```
Updated some stuff
fix bug
Added new feature.
FEAT: New Docker Container
wip: work in progress
```

### File Organization

✅ **Allowed:**
```
docker-compose.yml          # ≤ 10MB
inventory/servers.md         # No limit
.github/workflows/ci.yml     # ≤ 20MB
scripts/deployment.sh        # ≤ 5MB
docs/architecture.png        # ≤ 5MB
```

❌ **Rejected:**
```
secret-keys.txt              # Forbidden filename
large-dataset.csv            # > 5MB
application.exe              # Forbidden extension
private.key                  # Forbidden filename
```

## 🤝 Contributing

### Adding New Patterns

1. Edit configuration files in `.githooks/config/`
2. Test with relevant files
3. Update documentation
4. Commit changes

### Modifying Hooks

1. Edit hook files in `.githooks/hooks/`
2. Test thoroughly with various scenarios
3. Update version comments and documentation
4. Run setup script to install updates

### Adding New Utilities

1. Create new script in `.githooks/utils/`
2. Follow existing patterns for argument parsing and output
3. Make executable with `chmod +x`
4. Add help information and integration points
5. Update main hooks to use new utility

## 📄 License

This git hooks system is part of the home-lab-inventory project and follows the same licensing terms.

## 🆘 Support

For issues related to git hooks:
1. Check the troubleshooting section above
2. Run `.githooks/setup.sh --help` for setup issues
3. Use `--help` flag on individual utilities
4. Review git hook logs for detailed error information
5. Create an issue in the project repository with detailed error information

---

*Last updated: 2024-08-24*
*Compatible with: Git 2.0+, Python 3.6+, Bash 4.0+*
