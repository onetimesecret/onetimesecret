#!/usr/bin/env bash
#
# check-ci-secrets.sh
#
# GitHub Actions secrets are a different documentation surface than
# .env.reference (check-env-reference.sh): they're never read by the app at
# runtime, they're configured in Settings > Secrets and variables > Actions,
# and their audience is whoever maintains CI, not whoever deploys the app.
# The established convention in this repo is to document each workflow's
# secrets in that workflow's own header comment (see
# build-and-publish-oci-images.yml, bump-api-docs.yml). This makes that
# convention CI-checked instead of aspirational.
#
# A secret counts as "consumed" when a workflow references
# `secrets.SECRET_NAME` (`${{ secrets.X }}`, `${{ secrets.X || ... }}`, etc).
# Every consumed secret must be named somewhere in a `#` comment line in the
# SAME workflow file, or be listed in scripts/ci-secrets-ignore.txt with a
# reason (e.g. GITHUB_TOKEN, which GitHub injects automatically and is never
# configured as a repository secret).
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

WORKFLOW_DIR=".github/workflows"
IGNORE_FILE="scripts/ci-secrets-ignore.txt"

[[ -d "$WORKFLOW_DIR" ]] || { echo "FAIL: $WORKFLOW_DIR not found" >&2; exit 1; }
[[ -f "$IGNORE_FILE" ]] || { echo "FAIL: $IGNORE_FILE not found" >&2; exit 1; }

tmp_ignored=$(mktemp)
trap 'rm -f "$tmp_ignored"' EXIT

sed -e 's/#.*$//' -e 's/[[:space:]]//g' "$IGNORE_FILE" | grep -E '^[A-Z][A-Z0-9_]+$' | sort -u > "$tmp_ignored"

missing=""
missing_count=0
consumed_count=0

for wf in "$WORKFLOW_DIR"/*.yml; do
  consumed=$(grep -Eoh 'secrets\.[A-Za-z][A-Za-z0-9_]+' "$wf" 2>/dev/null | sed -E 's/^secrets\.//' | sort -u) || true
  [[ -z "$consumed" ]] && continue

  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    consumed_count=$((consumed_count + 1))

    if grep -q -x -F "$name" "$tmp_ignored"; then
      continue
    fi

    # Documented = named in some comment line in this same file (excluding
    # the `secrets.X` reference lines themselves, which don't explain it).
    if grep -E '^[[:space:]]*#' "$wf" | grep -q -F "$name"; then
      continue
    fi

    missing="${missing}${wf}: ${name}"$'\n'
    missing_count=$((missing_count + 1))
  done <<< "$consumed"
done

if [[ -n "$missing" ]]; then
  echo "FAIL: $missing_count consumed secret(s) not documented in their workflow's header comment, and not in $IGNORE_FILE:" >&2
  echo "$missing" | sed 's/^/  /' >&2
  echo "" >&2
  echo "Add a '#   SECRET_NAME   description' line to the workflow file that" >&2
  echo "consumes it, or add it to $IGNORE_FILE with a reason." >&2
  exit 1
fi

echo "PASS: every consumed GitHub Actions secret is documented in its workflow or explicitly ignored"
echo "  ($consumed_count consumed, $(wc -l < "$tmp_ignored" | tr -d ' ') ignored)"
exit 0
