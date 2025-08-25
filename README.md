# Home Lab Inventory

Complete documentation and management system for home lab infrastructure including servers, virtual machines, Docker containers, and CI/CD automation.

## 🏗️ Architecture Overview

This repository manages a comprehensive home lab environment with:

- **Physical Servers**: Proxmox hypervisor, NAS storage, dedicated container host
- **Virtual Machines**: Various Linux distributions for different services
- **Docker Containers**: Self-hosted applications and development tools
- **CI/CD Pipeline**: Hybrid GitHub Actions with local git hooks validation
- **Network Infrastructure**: VLAN-based segmentation with Docker macvlan networking

## 📁 Repository Structure

```
├── docs/                           # Architecture and setup documentation
│   ├── ci-cd-architecture.md      # CI/CD pipeline design and workflows
│   ├── github-runner-setup.md     # Self-hosted runner configuration
│   └── local-ci-hooks.md          # Git hooks local validation system
├── inventory/                      # Server and infrastructure documentation
│   ├── servers.md                 # Physical server specifications
│   ├── virtual-machines.md        # VM inventory and configurations
│   ├── docker-containers.md       # Container services and resources
│   └── commands-available.md      # Available tools and versions
├── dockermaster/                   # Docker container configurations
│   ├── github-runner/             # Self-hosted GitHub Actions runner
│   ├── portainer/                 # Container management UI
│   ├── rundeck/                   # Job automation platform
│   └── */                         # Other container services
├── .githooks/                      # Local CI validation system
│   ├── hooks/                     # Pre-commit, commit-msg, pre-push hooks
│   ├── utils/                     # Validation utilities and scripts
│   └── config/                    # Hook configuration and patterns
└── .github/                       # GitHub Actions workflows
    └── workflows/                 # CI/CD pipeline definitions
```

## 🚀 Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/luiscamaral/home-lab-inventory.git
cd home-lab-inventory
```

### 2. Setup Local CI Hooks

```bash
# Install git hooks for local validation
./.githooks/setup.sh

# Verify installation
ls -la .git/hooks/
```

### 3. Access Server Infrastructure

```bash
# Connect to main container host
ssh dockermaster

# Connect to hypervisor
ssh proxmox

# Connect to NAS
ssh nas
```

## 🔧 CI/CD System

### Local CI with Git Hooks

The repository includes comprehensive local CI validation:

- **Pre-commit**: YAML validation, secret detection, file checks, code quality
- **Commit-msg**: Conventional commits enforcement
- **Pre-push**: Comprehensive validation including tests and workflow checks

### GitHub Actions

Hybrid CI/CD pipeline using both GitHub-hosted and self-hosted runners:

- **GitHub-hosted**: Public operations, security scanning, PR validation
- **Self-hosted**: Private deployments, internal network access, direct container management

### Integration Benefits

- **Early Issue Detection**: Local hooks catch problems before CI/CD
- **Reduced Pipeline Failures**: Pre-validation reduces GitHub Actions failures
- **Faster Feedback**: Immediate validation during development
- **Cost Optimization**: Fewer failed CI/CD runs

## 📊 Infrastructure Components

### Physical Infrastructure

- **Proxmox Server**: Hypervisor hosting multiple VMs
- **NAS (Synology)**: Network-attached storage with NFS shares
- **Dockermaster**: Dedicated Ubuntu server for container workloads

### Network Architecture

- **LAN Network**: 192.168.48.0/20 (main network)
- **Docker Network**: 192.168.59.0/26 (macvlan for containers)
- **VLAN Segmentation**: Isolated networks for different services

### Container Services

Currently deployed containers on dockermaster:

- **GitHub Actions Runner**: Self-hosted CI/CD
- **Portainer**: Docker management UI
- **Rundeck**: Job automation and runbook execution
- **Bind9**: DNS server
- **Nginx**: Reverse proxy
- **Calibre**: E-book management server
- **PostgreSQL**: Database services

## 🔒 Security Features

### Local CI Security

- **Secret Detection**: Pattern-based scanning for hardcoded credentials
- **File Validation**: Size limits and type restrictions
- **Workflow Validation**: GitHub Actions security checks
- **Local-only Scanning**: Secrets never leave development environment

### Infrastructure Security

- **Network Isolation**: VLAN separation and firewall rules
- **Container Security**: Resource limits and read-only mounts
- **Access Control**: SSH key-based authentication
- **Token Management**: Secure credential handling

## 📚 Documentation

### Architecture Documentation

- [**CI/CD Architecture**](docs/ci-cd-architecture.md): Complete pipeline design and workflows
- [**GitHub Runner Setup**](docs/github-runner-setup.md): Self-hosted runner configuration
- [**Local CI Hooks**](docs/local-ci-hooks.md): Git hooks validation system

### Infrastructure Inventory

- [**Servers**](inventory/servers.md): Physical server specifications and configurations
- [**Virtual Machines**](inventory/virtual-machines.md): VM inventory with resources and purposes
- [**Docker Containers**](inventory/docker-containers.md): Container services and resource usage
- [**Available Commands**](inventory/commands-available.md): Tools and versions across servers

## 🛠️ Development Workflow

### Making Changes

1. **Clone and Setup**:
   ```bash
   git clone <repository>
   ./.githooks/setup.sh
   ```

2. **Create Feature Branch**:
   ```bash
   git checkout -b feature/new-service
   ```

3. **Make Changes**: Edit configurations, add services, update documentation

4. **Local Validation**: Git hooks automatically validate on commit/push

5. **Push and Deploy**:
   ```bash
   git push origin feature/new-service
   # Creates PR, triggers GitHub Actions
   ```

### Commit Message Format

Using [Conventional Commits](https://www.conventionalcommits.org/):

```bash
feat(docker): add nginx reverse proxy container
fix(security): resolve secret detection in workflows
docs(inventory): update server documentation
ci(github): add self-hosted runner support
chore: update dependencies and cleanup code
```

## 🔧 Maintenance

### Regular Tasks

- **Weekly**: Update container images and check resource usage
- **Monthly**: Review logs, rotate tokens, update documentation
- **Quarterly**: Security audit, dependency updates, capacity planning

### Monitoring

- **Container Health**: Portainer dashboards and Docker stats
- **CI/CD Performance**: GitHub Actions analytics and runner health
- **Infrastructure**: Server monitoring via SSH and system tools

## 🤝 Contributing

1. **Setup Environment**: Install git hooks and verify access
2. **Follow Standards**: Use conventional commits and test locally
3. **Update Documentation**: Keep inventory and architecture docs current
4. **Test Changes**: Verify locally before pushing
5. **Create PRs**: Use descriptive titles and link to issues

## 📋 Common Commands

### Infrastructure Management

```bash
# Check container status
ssh dockermaster 'docker ps'

# View container logs
ssh dockermaster 'docker logs -f container-name'

# Check VM status
ssh proxmox 'qm list'

# Check storage usage
ssh nas 'df -h'
```

### CI/CD Management

```bash
# Test hooks locally
.githooks/utils/yaml-validator.py .github/workflows/*.yml
.githooks/utils/secret-detector.sh file.txt

# Skip hooks temporarily
git commit --no-verify -m "emergency fix"
SKIP_TESTS=true git push origin main
```

### Docker Management

```bash
# Connect to dockermaster and manage containers
ssh dockermaster
cd /path/to/service
docker-compose up -d
docker-compose logs -f
```

## 📞 Support

- **Documentation**: Check docs/ directory for detailed guides
- **Issues**: Create GitHub issues for bugs or feature requests
- **Troubleshooting**: See individual documentation files for common problems
- **Git Hooks Help**: Run `.githooks/setup.sh --help` or check utils help

---

*Last updated: 2025-08-25*
*Repository: Home Lab Infrastructure Management*
*License: Private use only*
