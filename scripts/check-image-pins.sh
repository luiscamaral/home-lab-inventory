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
  # Watchtower itself — its own design uses :latest.
  '^containrrr/watchtower:latest$'
  # openspeedtest publishes the image as `openspeedtest/latest:*`,
  # so the colonless form below is *not* this; the tagged variant
  # `openspeedtest/latest` (no tag) is the actual upstream name.
  '^openspeedtest/latest$'
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

    # Find the tag: everything after the LAST colon, but only if that
    # colon is in the path-after-host portion. We approximate: take the
    # last colon, but ignore it if the part before contains `/` and the
    # part after looks like a port (only digits).
    if [[ "$raw" == *:* ]]; then
      tag="${raw##*:}"
      # If it looks numeric only (port), there's no tag.
      if [[ "$tag" =~ ^[0-9]+$ ]] && [[ "$raw" != */*:[0-9]* ]]; then
        # ambiguous host:port with no tag — treat as untagged.
        tag=""
      fi
    else
      tag=""
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
