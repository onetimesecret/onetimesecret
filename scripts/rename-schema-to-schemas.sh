#!/usr/bin/env bash
# Rename SCHEMA to SCHEMAS for hash-form declarations (handlers).
# Only matches lines where SCHEMA = { ... } (hash literal).
# Leaves SCHEMA = 'string' (model declarations) unchanged.
#
# Dry-run: bash scripts/rename-schema-to-schemas.sh
# Apply:   bash scripts/rename-schema-to-schemas.sh --apply

set -euo pipefail

APPLY=false
if [[ "${1:-}" == "--apply" ]]; then
  APPLY=true
fi

# Find all Ruby files with hash-form SCHEMA = { ... }
# Use grep -E (extended regex) for macOS compatibility
FILES=$(grep -rlE 'SCHEMA[[:space:]]*=[[:space:]]*\{' --include='*.rb' apps/ lib/ || true)

if [[ -z "$FILES" ]]; then
  echo "No files found with hash-form SCHEMA declarations."
  exit 0
fi

COUNT=0
for f in $FILES; do
  if grep -qE '^[[:space:]]*SCHEMA[[:space:]]*=' "$f"; then
    COUNT=$((COUNT + 1))
    if $APPLY; then
      # Replace SCHEMA = { with SCHEMAS = { (preserving indentation)
      # Only on lines containing = {
      sed -i '' '/=[[:space:]]*{/s/SCHEMA/SCHEMAS/' "$f"
      echo "UPDATED: $f"
    else
      echo "WOULD UPDATE: $f"
      grep -nE 'SCHEMA[[:space:]]*=[[:space:]]*\{' "$f" | head -5
    fi
  fi
done

echo ""
echo "Total files: $COUNT"
if ! $APPLY; then
  echo "(dry-run mode — pass --apply to make changes)"
fi
