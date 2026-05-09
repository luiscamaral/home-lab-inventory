#!/usr/bin/env bash
# Regenerate snmp.yml from generator.yml + MIBs in this directory.
#
# Output: ./snmp.yml (committed; community: stays as placeholder "public")
# Deploy: separate step, see README.md (currently a manual scp + restart;
#         migration to a baked image is tracked in the README's "Phase E"
#         note).
set -euo pipefail

cd "$(dirname "$0")"

# Build the helper image (idempotent; re-uses cache layers).
docker build -f Dockerfile.generator -t local/snmp-generator-with-mibs .

# Run the generator. --no-fail-on-parse-errors swallows the one harmless
# `Bad operator (INTEGER) at line 73 in SNMPv2-PDU` warning from the
# bundled IETF MIBs (known net-snmp parser quirk).
docker run --rm -v "$PWD:/opt" -w /opt --entrypoint /bin/generator \
  local/snmp-generator-with-mibs \
  generate --no-fail-on-parse-errors -g generator.yml -o snmp.yml

echo
echo "Generated snmp.yml: $(wc -l < snmp.yml) lines, $(grep -c '^    - name:' snmp.yml) walked metrics"
echo
echo "Deploy: see README.md. Until baked-image migration, the runtime"
echo "community string is injected by sed-substituting 'community: public'"
echo "with the value from Vault path secret/homelab/pfsense/snmp during scp."
