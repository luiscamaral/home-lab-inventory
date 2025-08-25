# Network Configuration

## Network Interfaces

### Physical Interfaces

| Interface | Type | MAC Address | IP Address/CIDR | State | MTU |
|-----------|------|-------------|-----------------|-------|-----|
| lo | loopback | 00:00:00:00:00:00 | 127.0.0.1/8 | UP | 65536 |
| ens19 | ethernet | 0a:c2:93:83:02:12 | 192.168.48.44/20 | UP | 1500 |

### Virtual Network Interfaces

| Interface | Type | MAC Address | IP Address/CIDR | State | MTU |
|-----------|------|-------------|-----------------|-------|-----|
| server-net-shim@ens19 | macvlan | 9a:3d:10:a1:b2:c3 | 192.168.59.1/26 | UP | 1500 |
| docker0 | bridge | 6e:8f:fd:15:74:48 | 172.17.0.1/16 | DOWN | 1500 |

### Docker Bridge Networks

| Interface | Network ID | MAC Address | IP Address/CIDR | State | MTU |
|-----------|------------|-------------|-----------------|-------|-----|
| br-17ead9c2db73 | 17ead9c2db73 | 16:a3:f5:64:46:f3 | 172.18.0.1/16 | UP | 1500 |
| br-3f745887f5bd | 3f745887f5bd | 72:97:b1:b8:18:34 | 172.22.0.1/16 | DOWN | 1500 |
| br-4af0ac3611e2 | 4af0ac3611e2 | a6:db:33:32:08:26 | 172.19.0.1/16 | UP | 1500 |
| br-7dbe68b3d124 | 7dbe68b3d124 | 3a:7c:82:a3:ec:8c | 172.23.0.1/16 | DOWN | 1500 |
| br-201b9300370c | 201b9300370c | 7a:e8:55:ba:b4:b1 | 172.20.0.1/16 | UP | 1500 |

### Container Virtual Ethernet Pairs

| Interface | Connected To | MAC Address | State | Bridge |
|-----------|--------------|-------------|-------|--------|
| vetha578e1c@if2 | Container namespace 1 | 66:08:c9:53:42:0d | UP | br-17ead9c2db73 |
| vethb1a0787@if2 | Container namespace 4 | 6e:fc:86:ff:35:77 | UP | br-4af0ac3611e2 |
| vethffb2b3d@if2 | Container namespace 0 | 12:5c:87:39:e7:70 | UP | br-201b9300370c |
| veth3a05f32@if2 | Container namespace 6 | 5e:e2:0b:1b:aa:f1 | UP | br-201b9300370c |

## Routing Table

| Destination | Gateway | Interface | Protocol | Scope | Metric |
|-------------|---------|-----------|----------|-------|--------|
| default | 192.168.48.1 | ens19 | static | - | - |
| 172.17.0.0/16 | - | docker0 | kernel | link | linkdown |
| 172.18.0.0/16 | - | br-17ead9c2db73 | kernel | link | - |
| 172.19.0.0/16 | - | br-4af0ac3611e2 | kernel | link | - |
| 172.20.0.0/16 | - | br-201b9300370c | kernel | link | - |
| 172.22.0.0/16 | - | br-3f745887f5bd | kernel | link | linkdown |
| 172.23.0.0/16 | - | br-7dbe68b3d124 | kernel | link | linkdown |
| 192.168.48.0/20 | - | ens19 | kernel | link | - |
| 192.168.59.0/26 | - | server-net-shim | kernel | link | - |
| 192.168.59.0/26 | - | server-net-shim | static | link | 100 |

## Network Configuration Summary

### Primary Network
- **Physical Interface**: ens19
- **IP Address**: 192.168.48.44/20 (255.255.240.0)
- **Gateway**: 192.168.48.1
- **Network Range**: 192.168.48.0 - 192.168.63.255

### Server Network Shim
- **Interface**: server-net-shim@ens19
- **IP Address**: 192.168.59.1/26
- **Network Range**: 192.168.59.0 - 192.168.59.63
- **Purpose**: Container network isolation

### Docker Networks
- **Default Docker Bridge**: 172.17.0.0/16 (currently down)
- **Active Docker Networks**:
  - br-17ead9c2db73: 172.18.0.0/16
  - br-4af0ac3611e2: 172.19.0.0/16
  - br-201b9300370c: 172.20.0.0/16
- **Inactive Docker Networks**:
  - br-3f745887f5bd: 172.22.0.0/16
  - br-7dbe68b3d124: 172.23.0.0/16

*Last updated: 2025-08-09*
