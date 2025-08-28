# Dockermaster Configurations

This directory contains global configuration files for dockermaster infrastructure.

## 📁 Directory Structure

- **nginx/**: Reverse proxy configurations
- **prometheus/**: Monitoring configurations
- **grafana/**: Dashboard configurations
- **vault/**: Secret management configurations
- **network/**: Network configuration files

## 🔧 Configuration Types

### Reverse Proxy (nginx)
- Site configurations
- SSL certificates
- Upstream definitions

### Monitoring (Prometheus/Grafana)
- Scrape configurations
- Alerting rules
- Dashboard definitions

### Security (Vault)
- Policy definitions
- Auth method configurations

### Network
- Docker network definitions
- Firewall rules
- DNS configurations

## 🔒 Security Notes

- Never commit sensitive configurations to git
- Use environment variables for secrets
- Store sensitive configs in Vault
- Use `.example` files for templates

---
*Last Updated: 2025-08-28*