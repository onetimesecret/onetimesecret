#!/usr/bin/env bash
#
# Rename AUTH_RECIPIENT -> RECIPIENT_AUTH and ANON_RECIPIENT -> RECIPIENT_ANON
# across the codebase.
#
# Usage: ./scripts/rename-recipient-roles.sh
#
# Files affected:
#   - src/apps/secret/composables/useSecretContext.ts
#   - src/tests/apps/secret/composables/useSecretContext.spec.ts
#   - src/tests/e2e/secret-context.spec.ts
#   - src/README.md
#   - docs/product/interaction-modes.md
#   - docs/product/assessments/vue-frontend-gap-analysis.md
#   - docs/product/tasks/interaction-modes-migration-manifest.md
#   - scripts/migration/migrate.ts
#

set -euo pipefail

echo "Renaming AUTH_RECIPIENT -> RECIPIENT_AUTH and ANON_RECIPIENT -> RECIPIENT_ANON"
echo ""

# Define files to update
FILES=(
  "src/apps/secret/composables/useSecretContext.ts"
  "src/tests/apps/secret/composables/useSecretContext.spec.ts"
  "src/tests/e2e/secret-context.spec.ts"
  "src/README.md"
  "docs/product/interaction-modes.md"
  "docs/product/assessments/vue-frontend-gap-analysis.md"
  "docs/product/tasks/interaction-modes-migration-manifest.md"
  "docs/test-cases/issue-2114-interaction-modes.md"
  "docs/test-cases/issue-2114-qase-import.csv"
  "scripts/migration/migrate.ts"
)

for file in "${FILES[@]}"; do
  if [[ -f "$file" ]]; then
    echo "Processing: $file"

    # macOS sed requires -i '' as separate arguments
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' -e 's/AUTH_RECIPIENT/RECIPIENT_AUTH/g' -e 's/ANON_RECIPIENT/RECIPIENT_ANON/g' "$file"
    else
      sed -i -e 's/AUTH_RECIPIENT/RECIPIENT_AUTH/g' -e 's/ANON_RECIPIENT/RECIPIENT_ANON/g' "$file"
    fi
  else
    echo "Skipping (not found): $file"
  fi
done

echo ""
echo "Done. Verify changes with:"
echo "  git diff"
echo ""
echo "If satisfied, commit with:"
echo "  git add -u && git commit -m 'Rename recipient roles to RECIPIENT_AUTH/RECIPIENT_ANON'"
