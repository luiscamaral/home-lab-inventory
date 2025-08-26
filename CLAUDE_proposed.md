# Inventory Project Configuration

## 🖥️ Infrastructure

| Server | Access | Sudo Setup | Notes |
|--------|--------|------------|-------|
| Proxmox | `ssh proxmox` | `SUDO_ASKPASS=$HOME/.config/bin/answer.sh` | Linux |
| NAS | `ssh nas` | - | Synology |
| Dockermaster | `ssh dockermaster` | `SUDO_ASKPASS=$HOME/.config/bin/answer` | Ubuntu, all containers |

**Docker Network**: `docker-servers-net` (192.168.48.0/20, macvlan)

- Containers run on internal LAN with internet access
- **TODO**: Implement passive Continuous Deployment from dockermaster

## 📁 Project Structure

```text
inventory/          # Infrastructure documentation
├── servers.md
├── virtual-machines.md  
├── docker-containers.md
└── commands-available.md
docs/              # Architecture, CI/CD, scripts
.github/           # GitHub workflows and templates
.githooks/         # Git hooks
deployment/        # Deployment configurations
dockermaster/      # Docker container definitions
README.md          # Project overview
```

## 🛠️ Development Workflow

### Core Tools & MCP Priority

1. **think-tool** → documentation → context7 → filesystem → **memory**
2. **Version Management**: Use `mise` for tool versions
3. **Docker**: Use `docker compose` (latest CE)
4. **Git**: Prefer GitHub MCP over `gh` command

### Memory MCP (Critical)

- **Before each task**: Use memory MCP to enhance context
- **Register**: entities, relations, and notes about the project
- Keep project well-identified in memory

### Task Management ⚠️ MANDATORY

- **_Always_ plan tasks and optimize subtasks for parallel execution**
- Deploy sub-agents with detailed instructions:
  - **Must** use think-tool + sequentialthinking
  - **Must** use Sonnet model
  - Provide very refined and detailed instructions

### Git Standards

- Create branches for major changes
- Commit between feature implementations  
- Keep branches for history (don't delete unless commanded)

## ✅ Quality Control

### Pre-commit/Push (NEVER IGNORE)

- Never commit/push with validation issues
- **Always**: Test → Fix → Commit → Push

### Error Analysis & Commands

```bash
# Count issues (don't just check first lines)
git push -n origin branch 2>&1 | grep -i -E "(error|warn|style)" | wc -l

# Filter errors (use grep for content filtering, NOT head/tail)
command | grep -B2 -A2 -i -E "(error|warn)"

# head or tail only to verify "any" line exists, not to filter specific content, and never together
```

### Cleanup Standards

- Remove temporary test scripts when ALL todo tasks completed
- No paid tools/frameworks (even with free tier)
- Use context7 to confirm documentation and latest versions
- Use semgrep MCP when tasks can benefit from security analysis

## 📌 Key Behavioral Rules

- **Do exactly what's asked** - nothing more, nothing less
- **Edit > Create** - modify existing files when possible
- **No proactive docs** - create *.md only when explicitly requested
- **Use multiple sub-agents** for organized todos with detailed instructions
- Always add a LINE at the end of every *.md file
