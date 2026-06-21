#!/usr/bin/env bash
#
# Creates one branch per locale with only that locale's content changes.
# Run from repo root with a clean working tree (stash or commit other changes first).
#
# Usage:
#   locales/scripts/branch-per-locale.sh [--dry-run] [--changed] [locale...]
#
# Options:
#   --changed   Only process locales with uncommitted changes (default if no locales specified)
#   --dry-run   Preview commands without executing (default)
#   --execute   Actually run the commands
#
# Examples:
#   locales/scripts/branch-per-locale.sh --changed          # All locales with changes
#   locales/scripts/branch-per-locale.sh ar bg ca_ES        # Specific locales only
#   locales/scripts/branch-per-locale.sh --dry-run --changed

set -euo pipefail

BASE_BRANCH=develop
CONTENT_DIR=locales/content
DRY_RUN=true
CHANGED_ONLY=false

die() { echo "error: $1" >&2; exit 1; }

# Parse arguments
LOCALES=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --execute) DRY_RUN=false ;;
    --changed) CHANGED_ONLY=true ;;
    --help|-h)
      sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) LOCALES+=("$arg") ;;
  esac
done

# Verify clean working tree (except locales/content which we expect to have changes)
if ! git diff --quiet -- ':!locales/content'; then
  die "working tree has uncommitted changes outside locales/content"
fi

# Verify base branch exists
git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1 || die "base branch '$BASE_BRANCH' not found"

# --changed or no locales specified: find all with changes
if $CHANGED_ONLY || [[ ${#LOCALES[@]} -eq 0 ]]; then
  CHANGED_ONLY=true
  LOCALES=()
  while IFS= read -r path; do
    locale=$(echo "$path" | cut -d/ -f3)
    [[ -n "$locale" ]] && LOCALES+=("$locale")
  done < <(git status --short "$CONTENT_DIR" | awk '{print $2}' | cut -d/ -f1-3 | sort -u)
fi

[[ ${#LOCALES[@]} -eq 0 ]] && die "no locales with changes found"

echo "Locales to process: ${LOCALES[*]}"
echo "Base branch: $BASE_BRANCH"
$DRY_RUN && echo "DRY RUN - no changes will be made"
echo

ORIGINAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)

for locale in "${LOCALES[@]}"; do
  locale_dir="$CONTENT_DIR/$locale"
  branch="i18n/update-${locale}"

  # Skip if no changes for this locale
  if ! git status --short "$locale_dir" | grep -q .; then
    echo "[$locale] no changes, skipping"
    continue
  fi

  # Check if branch already exists
  if git rev-parse --verify "$branch" >/dev/null 2>&1; then
    echo "[$locale] branch '$branch' already exists, skipping"
    continue
  fi

  echo "[$locale] creating branch '$branch'..."

  if $DRY_RUN; then
    echo "  would: git checkout $BASE_BRANCH"
    echo "  would: git checkout -b $branch"
    echo "  would: git add $locale_dir/"
    echo "  would: git commit -m 'Update $locale translations'"
    echo "  would: git push -u origin $branch"
  else
    git checkout "$BASE_BRANCH"
    git checkout -b "$branch"
    git add "$locale_dir/"
    git commit -m "Update $locale translations"
    git push -u origin "$branch"
  fi

  echo "[$locale] done"
  echo
done

# Return to original branch
if ! $DRY_RUN; then
  git checkout "$ORIGINAL_BRANCH"
fi

echo "Complete. Returned to $ORIGINAL_BRANCH"
