# 📋 Commit Message Conventions

This repository uses [Conventional Commits](https://www.conventionalcommits.org/) to ensure consistent and meaningful commit messages. All commits are automatically validated using commitlint and Husky hooks.

## 🚀 Quick Start

1. **Install dependencies:**

   ```bash
   npm install
   ```

2. **Run setup script:**

   ```bash
   ./setup-commitlint.sh
   ```

3. **Start committing with conventional format!**

## 📝 Commit Message Format

```
<type>(<scope>): <subject>

[optional body]

[optional footer]
```

### Examples

```bash
feat(docker): add nginx reverse proxy configuration
fix(security): update gitleaks config to ignore test files
docs(inventory): add documentation for new proxmox nodes
ci(workflows): add automated Docker image builds
config(proxmox): update VM resource allocations
chore(deps): update commitlint to latest version
```

## 🏷️ Types

| Type | Description | Use Cases |
|------|-------------|-----------|
| `feat` | New feature | Adding new containers, services, or functionality |
| `fix` | Bug fix | Fixing configuration errors, service issues |
| `docs` | Documentation | README updates, inline documentation |
| `style` | Code style changes | Formatting, whitespace (no functional changes) |
| `refactor` | Code refactoring | Restructuring without changing functionality |
| `perf` | Performance improvements | Optimizing configurations, resource usage |
| `test` | Testing | Adding or updating tests |
| `build` | Build system changes | Dependencies, build scripts |
| `ci` | CI/CD changes | GitHub workflows, automation |
| `chore` | Maintenance tasks | Routine updates, cleanup |
| `revert` | Revert changes | Undoing previous commits |
| `config` | Configuration changes | Infrastructure configuration updates |
| `deploy` | Deployment | Deployment-related changes |
| `security` | Security improvements | Security fixes, updates, hardening |

## 🎯 Scopes

Choose the most relevant scope for your change:

### Infrastructure Scopes

- `servers` - Physical server configurations
- `proxmox` - Proxmox hypervisor specific changes
- `nas` - NAS/Synology specific configurations
- `dockermaster` - Docker master server configurations
- `network` - Network configurations
- `storage` - Storage configurations

### Application Scopes

- `docker` - Docker containers and compose files
- `containers` - Container-specific changes
- `monitoring` - Monitoring and alerting systems
- `backup` - Backup configurations and scripts

### Development Scopes

- `docs` - Documentation updates
- `ci` - Continuous integration workflows
- `deploy` - Deployment configurations
- `security` - Security configurations (gitleaks, etc.)
- `inventory` - Inventory documentation updates
- `workflows` - GitHub workflow changes

## ✍️ Writing Good Commit Messages

### Subject Line Rules

- **Maximum 100 characters**
- **Use imperative mood** ("add" not "added" or "adds")
- **Start with lowercase** (except proper nouns)
- **No period at the end**
- **Be descriptive but concise**

### Good Examples

```bash
✅ feat(docker): add traefik reverse proxy with SSL
✅ fix(security): resolve gitleaks false positive for API keys
✅ docs(inventory): update server specs for node-04
✅ config(proxmox): increase VM memory allocation for monitoring
```

### Bad Examples

```bash
❌ feat: stuff
❌ Fix bug
❌ feat(docker): Added new container for nginx and configured it with SSL.
❌ WIP: working on docker stuff
```

## 🛠️ Tools and Commands

### Interactive Commit Creation

```bash
# Use commitizen for guided commit creation
npm run commit
```

### Validation Commands

```bash
# Validate last commit
npm run commitlint

# Validate last 10 commits
npm run validate:commits

# Check commit format for last 5 commits
npm run check:commit-format
```

### Git Template

The repository includes a commit message template:

```bash
# Template is automatically configured during setup
git commit  # Opens editor with template
```

## 🔧 Configuration Files

- `.commitlintrc.json` - Commitlint configuration
- `.gitmessage` - Git commit message template
- `package.json` - npm dependencies and scripts
- `.husky/commit-msg` - Husky commit message hook
- `.husky/pre-commit` - Husky pre-commit hook

## 🔀 Integration with Existing Tools

### Pre-commit Hooks

The setup integrates seamlessly with existing pre-commit hooks:

- Husky runs commitlint validation
- Pre-commit runs code quality checks
- Both must pass for successful commits

### Workflow

1. **Stage changes:** `git add .`
2. **Commit:** `git commit`
3. **Pre-commit runs:** Code linting, formatting, security checks
4. **Commit-msg runs:** Commit message validation
5. **Success:** Commit is created

## 🚨 Troubleshooting

### Common Issues

**Commit message validation fails:**

```bash
# Check your message format
echo "your commit message" | npx commitlint

# Use the interactive tool
npm run commit
```

**Husky hooks not running:**

```bash
# Reinstall hooks
npx husky install
```

**Pre-commit integration issues:**

```bash
# Check pre-commit status
pre-commit --version
pre-commit run --all-files
```

## 📚 Resources

- [Conventional Commits Specification](https://www.conventionalcommits.org/)
- [commitlint Documentation](https://commitlint.js.org/)
- [Husky Documentation](https://typicode.github.io/husky/)
- [Angular Commit Guidelines](https://github.com/angular/angular/blob/main/CONTRIBUTING.md#commit)

## 🤝 Getting Help

If you encounter issues or need clarification:

1. Check this documentation
2. Run `npm run check:commit-format` to validate recent commits
3. Use `npm run commit` for guided commit creation
4. Review the `.gitmessage` template for examples

Remember: Good commit messages help everyone understand the project's evolution and make debugging much easier! 🎯
