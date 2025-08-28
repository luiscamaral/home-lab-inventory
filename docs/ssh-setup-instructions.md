# SSH Multiplexing Setup Instructions

**Part of:** Dockermaster Recovery - Documentation Framework  
**Created:** 2025-08-28  
**Purpose:** Enable efficient SSH connections for documentation automation

## 🎯 Overview

SSH multiplexing allows multiple SSH sessions to share a single connection, dramatically improving performance for automation scripts that need to execute multiple commands on dockermaster.

## 📝 Required SSH Configuration

Add the following configuration to your `~/.ssh/config` file:

```bash
# Dockermaster with SSH Multiplexing for Documentation Framework
Host dockermaster
    HostName dockermaster
    User lamaral
    ControlMaster auto
    ControlPath ~/.ssh/master-%r@%h:%p
    ControlPersist 10m
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

## 🔧 Configuration Explanation

- **ControlMaster auto**: Automatically creates master connection when needed
- **ControlPath ~/.ssh/master-%r@%h:%p**: Socket file location for connection sharing
- **ControlPersist 10m**: Keep connection alive for 10 minutes after last use
- **ServerAliveInterval 60**: Send keepalive every 60 seconds
- **ServerAliveCountMax 3**: Close connection after 3 failed keepalives

## 🚀 Setup Steps

### 1. Update SSH Configuration

```bash
# Edit your SSH config
vim ~/.ssh/config

# Add the dockermaster configuration block above
```

### 2. Test SSH Helper Script

```bash
# Make sure the script is executable (already done)
chmod +x scripts/ssh-dockermaster.sh

# Test the configuration
./scripts/ssh-dockermaster.sh test
```

### 3. Verify Multiplexing Works

```bash
# Connect to dockermaster
./scripts/ssh-dockermaster.sh connect

# Check status
./scripts/ssh-dockermaster.sh status

# Execute a test command
./scripts/ssh-dockermaster.sh exec "hostname"

# Test performance with multiple commands
./scripts/ssh-dockermaster.sh exec "docker ps --format 'table {{.Names}}\t{{.Status}}'"
```

## 📊 Performance Benefits

With SSH multiplexing enabled:

- **First connection**: ~2-3 seconds
- **Subsequent commands**: ~0.1-0.3 seconds
- **Automation scripts**: 5-10x faster execution
- **Reduced server load**: Single TCP connection instead of multiple

## 🛠️ SSH Helper Script Usage

The `scripts/ssh-dockermaster.sh` script provides convenient commands:

### Connection Management
```bash
./scripts/ssh-dockermaster.sh connect      # Establish persistent connection
./scripts/ssh-dockermaster.sh disconnect   # Close connection
./scripts/ssh-dockermaster.sh status       # Check connection status
```

### Command Execution
```bash
./scripts/ssh-dockermaster.sh exec "docker ps"
./scripts/ssh-dockermaster.sh exec "ls /nfs/dockermaster/docker/"
./scripts/ssh-dockermaster.sh shell        # Interactive session
```

### Testing and Troubleshooting
```bash
./scripts/ssh-dockermaster.sh test         # Full functionality test
./scripts/ssh-dockermaster.sh help         # Show usage information
```

## 🔍 Troubleshooting

### Common Issues

1. **"Connection refused"**
   - Ensure dockermaster is accessible
   - Check network connectivity
   - Verify SSH service is running on dockermaster

2. **"Host not found"**
   - Ensure "dockermaster" resolves to correct IP
   - Consider using IP address directly in SSH config

3. **"Permission denied"**
   - Check SSH key authentication
   - Verify user account on dockermaster
   - Test manual SSH connection first

4. **Control socket errors**
   - Clean up stale socket: `rm ~/.ssh/master-*`
   - Restart SSH multiplexing: `./scripts/ssh-dockermaster.sh disconnect && ./scripts/ssh-dockermaster.sh connect`

### Manual Testing

```bash
# Test basic SSH connection
ssh dockermaster "hostname"

# Test SSH multiplexing manually
ssh -M -S ~/.ssh/master-test dockermaster  # Master connection
ssh -S ~/.ssh/master-test dockermaster "docker ps"  # Use existing connection
ssh -O exit -S ~/.ssh/master-test dockermaster  # Close connection
```

## 🎯 Integration with Automation Scripts

The SSH multiplexing setup is designed to work with the documentation automation tools:

1. **extract-compose.sh** - Extract docker-compose.yml files
2. **parse-env.sh** - Parse environment variables
3. **find-deps.sh** - Identify service dependencies

These scripts will automatically use the multiplexed connection when available, providing significant performance improvements during bulk documentation tasks.

## 📋 Validation Checklist

Before proceeding to Task 3.3 (automation tools), verify:

- [ ] SSH config updated with multiplexing options
- [ ] `ssh-dockermaster.sh` script is executable
- [ ] Test connection successful: `./scripts/ssh-dockermaster.sh test`
- [ ] Status check works: `./scripts/ssh-dockermaster.sh status`
- [ ] Command execution works: `./scripts/ssh-dockermaster.sh exec "hostname"`
- [ ] Connection persistence verified (stays alive for 10 minutes)

## 🔜 Next Steps

Once SSH multiplexing is configured and tested:

1. **Task 3.3**: Create documentation automation tools
2. **Testing**: Validate scripts on known services
3. **Bulk Documentation**: Use tools to document remaining 20 services

---

**Note**: This setup is part of the dockermaster-recovery documentation framework and is essential for efficient bulk documentation tasks.