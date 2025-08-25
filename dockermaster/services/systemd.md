# Systemd Services

## Running Services

The following systemd services are currently active and running on dockermaster:

| Service | Load | Active | Sub | Description |
|---------|------|--------|-----|-------------|
| btop-tty1.service | loaded | active | running | BTOP++ System Monitor on Terminal 1 (tty1) |
| containerd.service | loaded | active | running | containerd container runtime |
| cron.service | loaded | active | running | Regular background program processing daemon |
| dbus.service | loaded | active | running | D-Bus System Message Bus |
| docker.service | loaded | active | running | Docker Application Container Engine |
| iperf3.service | loaded | active | running | iperf3 server |
| multipathd.service | loaded | active | running | Device-Mapper Multipath Device Controller |
| ntpsec.service | loaded | active | running | Network Time Service |
| polkit.service | loaded | active | running | Authorization Manager |
| qemu-guest-agent.service | loaded | active | running | QEMU Guest Agent |
| rpcbind.service | loaded | active | running | RPC bind portmap service |
| rsyslog.service | loaded | active | running | System Logging Service |
| snapd.service | loaded | active | running | Snap Daemon |
| ssh.service | loaded | active | running | OpenBSD Secure Shell server |
| systemd-journald.service | loaded | active | running | Journal Service |
| systemd-logind.service | loaded | active | running | User Login Management |
| systemd-networkd.service | loaded | active | running | Network Configuration |
| systemd-resolved.service | loaded | active | running | Network Name Resolution |
| systemd-udevd.service | loaded | active | running | Rule-based Manager for Device Events and Files |

## Service Categories

### Container Runtime Services
- **containerd.service**: Container runtime daemon
- **docker.service**: Docker Application Container Engine

### System Services
- **systemd-journald.service**: System logging and journal management
- **systemd-logind.service**: User session management
- **systemd-networkd.service**: Network configuration management
- **systemd-resolved.service**: DNS resolution service
- **systemd-udevd.service**: Device management

### Network Services
- **ssh.service**: SSH server for remote access
- **rpcbind.service**: RPC portmapper for NFS
- **iperf3.service**: Network performance testing server

### System Management
- **cron.service**: Scheduled task execution
- **dbus.service**: Inter-process communication
- **polkit.service**: Privilege escalation authorization
- **rsyslog.service**: System event logging
- **ntpsec.service**: Network time synchronization

### Hardware & Virtualization
- **qemu-guest-agent.service**: Guest agent for VM management
- **multipathd.service**: Multipath storage device management

### Monitoring & Package Management
- **btop-tty1.service**: System resource monitoring on TTY1
- **snapd.service**: Snap package manager daemon

## Service Status Summary

- **Total Services Listed**: 19 running services
- **All Services Status**: Active and running
- **Load Status**: All services properly loaded
- **Critical Services**: docker.service, containerd.service, ssh.service are operational
- **Monitoring**: System monitoring active via btop on TTY1

*Last updated: 2025-08-09*
