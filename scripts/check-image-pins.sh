#!/usr/bin/env bash
# Pre-commit guard: fail the commit if any Compose / Terraform-template
# file ships a Docker image without a real version tag.
#
# Reject patterns:
#   image: foo/bar:latest                       (explicit :latest)
#   image: foo/bar                              (no tag at all)
#   image: registry.example.com/internal:dev    (rejected only if dev/edge/master)
#
# Allowed:
#   image: foo/bar:1.2.3
#   image: foo/bar:v1.2
#   image: foo/bar:RELEASE.2025-09-07T16-13-09Z
#   image: foo/bar:9.20-24.10_edge              (date-bound stable, e.g. ubuntu/bind9)
#   image: postgres:17                          (numeric-only tag is a tag, not a port)
#   image: host:5000/repo:1.0                   (port in the host part is not the tag)
#
# Rejected as untagged: `registry:5000`, `registry.local:5000`, `localhost:5000`,
# `host:5000/repo` (host:port with no tag). See tests/test_check_image_pins.py.
#
# An allowlist exists for images that legitimately float: watchtower-
# managed sidecars and internally rebuilt registry images. Document
# every entry inline so future readers know why.
#
# Inputs: pre-commit passes the changed files as $@.
# Exit 0 = clean, Exit 1 = at least one offender (file:line printed).

set -euo pipefail

# Allowlist: images that intentionally use :latest. Patterns are matched
# against the full image string (everything after `image: `). Be SPECIFIC.
ALLOWLIST_REGEX=(
  # Internal registry — rebuilt on every CI push, :latest IS the contract.
  '^registry\.cf\.lcamaral\.com/.+:latest$'
  # Zot (successor to the registry above) — same contract for homelab/*.
  '^zot\.d\.lcamaral\.com/homelab/.+:latest$'
  # Watchtower itself — its own design uses :latest.
  '^containrrr/watchtower:latest$'
  # openspeedtest publishes the image as `openspeedtest/latest:*`,
  # so the colonless form below is *not* this; the tagged variant
  # `openspeedtest/latest` (no tag) is the actual upstream name.
  '^openspeedtest/latest$'
  # calibre-web (ds-1) carries com.centurylinklabs.watchtower.enable=true,
  # so Watchtower owns its update cadence; LinuxServer.io publishes a
  # rolling :latest and tracking it is intentional.
  # NOTE: linuxserver/calibre (desktop) was REMOVED from this list on
  # 2026-10-17 and is now pinned — a silent KasmVNC→Selkies base swap via
  # Watchtower broke its HTTP access path. See terraform/portainer/stacks/calibre.yml.
  '^lscr\.io/linuxserver/calibre-web:latest$'
)

# Reject patterns for the tag portion (after the colon). Matches indicate
# a floating tag we want to fail on.
REJECT_TAG_REGEX='^(latest|edge|master|main|dev|nightly|stable)$'

# Files with no args means scan nothing (pre-commit already filtered).
if [ "$#" -eq 0 ]; then
  exit 0
fi

violations=0

for file in "$@"; do
  # Skip if file no longer exists (pre-commit can pass deleted files).
  [ -f "$file" ] || continue

  # Walk every `image:` line. Use grep -n for line numbers.
  while IFS=: read -r line_no rest; do
    # Strip the matched `image:` prefix and surrounding whitespace.
    raw=$(echo "$rest" | sed -E 's/^[[:space:]]*image:[[:space:]]*//; s/[[:space:]]+$//')

    # Skip empty / templated-only entries (e.g. ${IMAGE_REF}).
    [[ -z "$raw" ]] && continue
    [[ "$raw" =~ ^\$ ]] && continue

    # Allowlisted? Pass.
    allowed=0
    for pattern in "${ALLOWLIST_REGEX[@]}"; do
      if [[ "$raw" =~ $pattern ]]; then
        allowed=1
        break
      fi
    done
    [ "$allowed" -eq 1 ] && continue

    # Extract tag. Image may be `repo`, `repo:tag`, `host:port/repo:tag`,
    # `repo@sha256:...`. Digest pin is always acceptable.
    if [[ "$raw" == *"@sha256:"* ]]; then
      continue
    fi

    # Find the tag. Only a colon in the LAST path component (after the final
    # `/`) can introduce a tag; an earlier colon is a registry port
    # (`host:5000/repo` has no tag).
    #
    # A bare `name:digits` with no `/` is ambiguous: `postgres:17` is a repo
    # with a numeric tag, `registry:5000` is a host:port with no repo.
    # Docker itself reads the former as tag. We treat it as host:port (no
    # tag) only when it looks like one: the name contains a dot or is
    # `localhost` (a hostname), or the number has 4-5 digits (a port; real
    # numeric tags such as 7, 8, 17 are shorter).
    last="${raw##*/}"
    tag=""
    if [[ "$last" == *:* ]]; then
      tag="${last##*:}"
      if [[ "$raw" != */* ]] && [[ "$tag" =~ ^[0-9]+$ ]]; then
        name="${last%:*}"
        if [[ "$name" == *.* || "$name" == "localhost" || "$tag" =~ ^[0-9]{4,5}$ ]]; then
          tag=""
        fi
      fi
    fi

    if [[ -z "$tag" ]]; then
      echo "ERROR: $file:$line_no — image without tag: $raw"
      violations=$((violations + 1))
      continue
    fi

    if [[ "$tag" =~ $REJECT_TAG_REGEX ]]; then
      echo "ERROR: $file:$line_no — floating tag '$tag': $raw"
      violations=$((violations + 1))
    fi
  done < <(grep -nE '^[[:space:]]*image:' "$file" || true)
done

if [ "$violations" -gt 0 ]; then
  echo ""
  echo "Found $violations image(s) without a pinned version tag."
  echo "Pin to a specific version (e.g. nginx:1.29-otel, postgres:17.6)."
  echo "If the image legitimately floats, add it to the ALLOWLIST in"
  echo "scripts/check-image-pins.sh with a comment explaining why."
  exit 1
fi

exit 0
