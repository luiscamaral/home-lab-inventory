# Dockermaster System Information

## Operating System

| Property | Value |
|----------|-------|
| Name | Ubuntu |
| Version | 24.04.2 LTS (Noble Numbat) |
| Pretty Name | Ubuntu 24.04.2 LTS |
| Codename | noble |
| Architecture | x86_64 |
| Kernel | Linux dockermaster 6.8.0-64-generic |
| Kernel Build | #67-Ubuntu SMP PREEMPT_DYNAMIC Sun Jun 15 20:23:31 UTC 2025 |

## Hardware Specifications

### CPU Information

| Property | Value |
|----------|-------|
| Model | Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz |
| Architecture | x86_64 |
| CPU Family | 6 |
| Model Number | 62 |
| Stepping | 4 |
| Total CPUs | 20 |
| Sockets | 2 |
| Cores per Socket | 10 |
| Threads per Core | 1 |
| Virtualization | VT-x (KVM Hypervisor) |
| BogoMIPS | 5586.53 |

### CPU Cache

| Cache Level | Size |
|-------------|------|
| L1d cache | 640 KiB (20 instances) |
| L1i cache | 640 KiB (20 instances) |
| L2 cache | 80 MiB (20 instances) |
| L3 cache | 32 MiB (2 instances) |

### Memory

| Type | Total | Used | Free | Available |
|------|-------|------|------|-----------|
| RAM | 62Gi | 4.2Gi | 50Gi | 58Gi |
| Swap | 8.0Gi | 0B | 8.0Gi | 8.0Gi |

### Storage

| Device | Filesystem | Size | Used | Available | Use% | Mount Point |
|--------|------------|------|------|-----------|------|-------------|
| /dev/sda2 | ext4 | 192G | 64G | 119G | 35% | / |
| tmpfs | tmpfs | 6.3G | 1.8M | 6.3G | 1% | /run |
| tmpfs | tmpfs | 32G | 0 | 32G | 0% | /dev/shm |
| tmpfs | tmpfs | 5.0M | 0 | 5.0M | 0% | /run/lock |

## Block Devices

| Device | Size | Type | Mount Point |
|--------|------|------|-------------|
| sda | 196G | disk | - |
| ├─sda1 | 1M | partition | - |
| └─sda2 | 196G | partition | / |

## Security Features

### CPU Vulnerabilities Mitigation

| Vulnerability | Status |
|---------------|--------|
| Gather data sampling | Not affected |
| Itlb multihit | Not affected |
| L1tf | Mitigation; PTE Inversion; VMX flush not necessary, SMT disabled |
| Mds | Mitigation; Clear CPU buffers; SMT Host state unknown |
| Meltdown | Mitigation; PTI |
| Mmio stale data | Unknown: No mitigations |
| Spectre v1 | Mitigation; usercopy/swapgs barriers and __user pointer sanitization |
| Spectre v2 | Mitigation; Retpolines; IBPB conditional; IBRS_FW; STIBP disabled; RSB filling |

*Last updated: 2025-08-09*