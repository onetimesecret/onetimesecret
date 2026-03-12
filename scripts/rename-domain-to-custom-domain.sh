#!/usr/bin/env bash
# scripts/rename-domain-to-custom-domain.sh
#
# Rename src/schemas/models/domain/ → src/schemas/models/custom-domain/
# and update all import paths project-wide.
#
# Preview with: bash scripts/rename-domain-to-custom-domain.sh --dry-run
# Execute with: bash scripts/rename-domain-to-custom-domain.sh

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

SRC="src/schemas/models/domain"
DST="src/schemas/models/custom-domain"

# 1. Move the directory
echo "=== Step 1: Rename directory ==="
if [[ "$DRY_RUN" == true ]]; then
  echo "  [dry-run] git mv $SRC $DST"
else
  git mv "$SRC" "$DST"
  echo "  Moved $SRC → $DST"
fi

# 2. Update import paths in TypeScript/Vue files
#    Pattern: schemas/models/domain → schemas/models/custom-domain
echo ""
echo "=== Step 2: Update import paths ==="

# Find all .ts, .vue files that reference the old path
FILES=$(grep -rl "schemas/models/domain" --include='*.ts' --include='*.vue' --include='*.rb' . 2>/dev/null || true)

if [[ -z "$FILES" ]]; then
  echo "  No files to update (already renamed or dry-run after move)"
else
  for f in $FILES; do
    if [[ "$DRY_RUN" == true ]]; then
      echo "  [dry-run] Update: $f"
    else
      # macOS sed requires '' after -i
      sed -i '' 's|schemas/models/domain|schemas/models/custom-domain|g' "$f"
      echo "  Updated: $f"
    fi
  done
fi

# 3. Update internal file-path comments inside the renamed files
echo ""
echo "=== Step 3: Update internal comments ==="
COMMENT_FILES=$(find "$( [[ "$DRY_RUN" == true ]] && echo "$SRC" || echo "$DST" )" -name '*.ts' 2>/dev/null || true)
for f in $COMMENT_FILES; do
  if [[ "$DRY_RUN" == true ]]; then
    echo "  [dry-run] Update comment in: $f"
  else
    sed -i '' 's|// src/schemas/models/domain|// src/schemas/models/custom-domain|g' "$f"
    echo "  Updated comment: $f"
  fi
done

echo ""
echo "=== Done ==="
if [[ "$DRY_RUN" == true ]]; then
  echo "Re-run without --dry-run to apply changes."
else
  echo "Run 'pnpm run type-check' to verify."
fi
