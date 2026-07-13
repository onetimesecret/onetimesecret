#!/usr/bin/env bash
#
# Exports every fully drained locale's translations from the SQLite DB into
# locales/content/, then exports the shared DB tables once. Leaves the changes
# uncommitted in the working tree for branch-per-locale.sh to split up.
#
# A locale is only exported when its task stats show pending: 0. Locales with
# pending tasks are skipped and reported (drain them first).
#
# Usage:
#   locales/scripts/export-all.sh [--dry-run] [--execute] [locale...]
#
# Options:
#   --dry-run   Preview without writing (default)
#   --execute   Actually run the exports
#
# Examples:
#   locales/scripts/export-all.sh --execute            # all drained locales + shared tables
#   locales/scripts/export-all.sh ar bg ca_ES          # preview specific locales
#   locales/scripts/export-all.sh --execute ar bg      # export specific locales only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCALES_DIR="$(dirname "$SCRIPT_DIR")"
CONTENT_DIR="$LOCALES_DIR/content"
I18N="$SCRIPT_DIR/i18n"

DRY_RUN=true

die() { echo "error: $1" >&2; exit 1; }

# Parse arguments
LOCALES=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --execute) DRY_RUN=false ;;
    --help|-h)
      sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    -*) die "unknown option: $arg" ;;
    *) LOCALES+=("$arg") ;;
  esac
done

# Default to every locale dir under content/ (exclude en, hidden)
if [[ ${#LOCALES[@]} -eq 0 ]]; then
  while IFS= read -r locale; do
    LOCALES+=("$locale")
  done < <(find "$CONTENT_DIR" -mindepth 1 -maxdepth 1 -type d \
    ! -name ".*" ! -name "en" -exec basename {} \; | sort)
fi

[[ ${#LOCALES[@]} -eq 0 ]] && die "no locales found in $CONTENT_DIR"

echo "Locales to consider: ${LOCALES[*]}"
$DRY_RUN && echo "DRY RUN - no changes will be made"
echo

# pending count for a locale (empty if stats unavailable)
pending_count() {
  local locale="$1"
  python3 "$I18N" tasks next "$locale" --stats --json 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('pending',''))" 2>/dev/null || echo ""
}

exported=0
skipped=0
not_drained=()

for locale in "${LOCALES[@]}"; do
  pending="$(pending_count "$locale")"

  if [[ -z "$pending" ]]; then
    echo "[$locale] no task stats (not in DB?), skipping"
    ((skipped++)) || true
    continue
  fi

  if [[ "$pending" -ne 0 ]]; then
    echo "[$locale] $pending task(s) still pending, skipping (drain first)"
    not_drained+=("$locale")
    ((skipped++)) || true
    continue
  fi

  echo "[$locale] drained (pending: 0), exporting..."
  if $DRY_RUN; then
    echo "  would: i18n tasks export $locale"
  else
    python3 "$I18N" tasks export "$locale"
  fi
  ((exported++)) || true
done

echo
# Shared tables (glossary, session_log, translation_issues) — once, after locales.
echo "Shared DB tables (glossary + translation_issues + session_log)..."
if $DRY_RUN; then
  echo "  would: i18n db export"
else
  python3 "$I18N" db export
fi

echo
echo "Done: $exported locale(s) exported, $skipped skipped"
if [[ ${#not_drained[@]} -gt 0 ]]; then
  echo "Not drained (skipped): ${not_drained[*]}"
fi
$DRY_RUN && echo "Re-run with --execute to apply."

exit 0
