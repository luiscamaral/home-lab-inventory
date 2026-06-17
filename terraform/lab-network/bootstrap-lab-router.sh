#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2029  # $HOME + sudo string are intentionally evaluated on the remote
# Reproducible provisioning for the lab-router (Proxmox VM 130, FRR-on-Debian).
#
# WHY a script and not Terraform: bpg/proxmox needs root-level SSH to Proxmox to upload the
# cloud-init snippet (root-owned local:snippets) + import the disk; this host disables direct
# root SSH (escalate via sudo only). Until a dedicated bpg deploy-SSH key is authorized (a
# security-posture decision — see README), the router is bootstrapped here, idempotently, from
# version control. Run from the workstation; uses `ssh proxmox` + the askpass sudo helper.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
VMID=130
IMG="/var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2"
IMG_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
ASKPASS='SUDO_ASKPASS=$HOME/.config/bin/answer.sh sudo -A'

echo "[1/4] vmbr30 internal bridge (idempotent)"
ssh proxmox "${ASKPASS} bash -s" <<'EOF'
if ! grep -q "iface vmbr30" /etc/network/interfaces; then
  cp /etc/network/interfaces /etc/network/interfaces.bak-labrouter
  printf '\nauto vmbr30\niface vmbr30 inet manual\n\tbridge-ports none\n\tbridge-stp off\n\tbridge-fd 0\n' >> /etc/network/interfaces
  ifreload -a
fi
EOF

echo "[2/4] Debian cloud image (idempotent)"
ssh proxmox "${ASKPASS} bash -c '[ -f ${IMG} ] || curl -fsSL -o ${IMG} ${IMG_URL}'"

echo "[3/4] stage cloud-init snippet from repo"
ssh proxmox "${ASKPASS} tee /var/lib/vz/snippets/lab-router-user.yaml >/dev/null" < "${REPO_DIR}/cloud-init/lab-router.yaml"

echo "[4/4] create + start VM ${VMID} (guarded if it exists)"
ssh proxmox "${ASKPASS} bash -s" <<EOF
VMID=${VMID}; IMG=${IMG}
if qm status \${VMID} >/dev/null 2>&1; then echo "VM \${VMID} already exists — skipping create"; exit 0; fi
qm create \${VMID} --name lab-router --memory 2048 --cores 2 --cpu host --ostype l26 \\
  --scsihw virtio-scsi-single --agent enabled=1 --serial0 socket --vga serial0 \\
  --net0 virtio,bridge=vmbr30,macaddr=BC:24:11:30:00:01 \\
  --net1 virtio,bridge=vmbr28 --net2 virtio,bridge=vmbr10 --net3 virtio,bridge=vmbr0
qm importdisk \${VMID} "\${IMG}" thin-pool-ssd
qm set \${VMID} --scsi0 thin-pool-ssd:vm-\${VMID}-disk-0 --boot order=scsi0 --ide2 thin-pool-ssd:cloudinit
qm set \${VMID} --ipconfig0 ip=192.168.30.1/24 --ipconfig1 ip=192.168.48.2/20,gw=192.168.48.1 \\
  --ipconfig2 ip=192.168.7.2/20 --ipconfig3 ip=192.168.100.2/24 --nameserver 192.168.4.1 --ciuser debian
qm set \${VMID} --cicustom "user=local:snippets/lab-router-user.yaml"
qm resize \${VMID} scsi0 8G
qm start \${VMID}
EOF

echo "Done. Verify: ssh proxmox '${ASKPASS} ssh -i /root/.ssh/id_ed25519 debian@192.168.7.2 \"sudo vtysh -c \\\"show ip bgp summary\\\"\"'"
