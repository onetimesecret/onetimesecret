#!/usr/bin/env bash
#
# Rename branded_homepage to homepage_secrets in locale billing files.
# Affects JSON keys only (values are translated text, not identifiers).
#
# This script is idempotent — safe to run multiple times.

set -euo pipefail

LOCALES_DIR="$(cd "$(dirname "$0")/.." && pwd)/content"
CHANGED=0

for file in "$LOCALES_DIR"/*/workspace-billing.json; do
  if grep -q 'branded_homepage' "$file" 2>/dev/null; then
    sed -i '' 's/branded_homepage/homepage_secrets/g' "$file"
    echo "Updated: $file"
    CHANGED=$((CHANGED + 1))
  fi
done

if [ "$CHANGED" -eq 0 ]; then
  echo "No files needed updating (already renamed or no matches found)."
else
  echo "Done. Updated $CHANGED file(s)."
fi
