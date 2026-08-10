#!/usr/bin/env bash
#
# Exports every fully drained AND clean locale's translations from the SQLite DB
# into locales/content/, then exports the shared DB tables once. Leaves the
# changes uncommitted in the working tree for branch-per-locale.sh to split up.
#
# A locale is exported only when both gates pass:
#   1. task stats show pending: 0 (drained)
#   2. `i18n tasks audit <locale> --strict` is clean — no stranded in_progress
#      row, no key-set/blank-translation defect, no token loss, and at least one
#      completed row actually checked
# pending: 0 alone does not prove the writes are clean, so the audit is the real
# gate; locales failing either one are skipped and named in the summary. The
# audit's en_leak check is advisory (an identical string is the correct
# translation for many short labels) and never blocks an export — its count is
# echoed on the TOTAL line; run `i18n tasks audit <locale>` for the detail.
#
# After a successful export the content is re-checked in the working tree:
#   - `i18n validate variables --locale <locale> --json` (placeholder parity),
#     gated on the report's own `blocking` count. Only each entry's `text` is
#     compared (authoring metadata is metadata), and untranslated keys are
#     reported but not blocking — coverage is gate 1's job, above
#   - the register lint, when .translation-rules/ and generated/i18n/.resolved/
#     exist (run locales/scripts/derive-governance.sh); skipped otherwise, and a
#     skip never fails the run
# A locale failing those is reported as dirty. Nothing is reverted — the point is
# to surface the problem while the content is still unstaged.
#
# Exit status is non-zero if any locale failed the audit, failed to export, or
# landed dirty; a locale that is merely not drained is a normal state and exits
# 0. The loop never aborts early: every locale is processed, then reported.
#
# Usage:
#   locales/scripts/export-all.sh [--dry-run] [--execute] [locale...]
#
# Options:
#   --dry-run   Preview without writing (default). Still runs the read-only
#               audit gate, so a dirty locale is reported (and exits non-zero)
#               before you commit to --execute.
#   --execute   Actually run the exports
#
# Examples:
#   locales/scripts/export-all.sh --execute            # all clean drained locales + shared tables
#   locales/scripts/export-all.sh ar bg ca_ES          # preview specific locales
#   locales/scripts/export-all.sh --execute ar bg      # export specific locales only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCALES_DIR="$(dirname "$SCRIPT_DIR")"
ROOT="$(dirname "$LOCALES_DIR")"
CONTENT_DIR="$LOCALES_DIR/content"
I18N="$SCRIPT_DIR/i18n"

# Register lint (governance-derived; absent unless derive-governance.sh has run).
RULES_LINT_REL=".translation-rules/lib/resolver/lint_content.py"
RESOLVED_DIR_REL="generated/i18n/.resolved"

DRY_RUN=true

die() { echo "error: $1" >&2; exit 1; }
indent() { sed 's/^/  /'; }

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

# The audit is the gate. An i18n CLI without it would let every locale through
# unchecked, so fail closed here rather than failing open per locale.
python3 "$I18N" tasks audit --help >/dev/null 2>&1 \
  || die "this i18n CLI has no 'tasks audit' subcommand; the export gate cannot run"

echo "Locales to consider: ${LOCALES[*]}"
$DRY_RUN && echo "DRY RUN - no changes will be made (the audit gate still runs; it is read-only)"
echo

# pending count for a locale (empty if stats unavailable)
pending_count() {
  local locale="$1"
  python3 "$I18N" tasks next "$locale" --stats --json 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('pending',''))" 2>/dev/null || echo ""
}

# Pre-export gate: the DB rows themselves (stranded rows, key sets, tokens).
# 0 = clean, 1 = error findings, nothing verified, or the audit could not run.
# en_leak findings are advisory in the audit and do not gate here either.
audit_locale() {
  local locale="$1" out rc=0
  out="$(python3 "$I18N" tasks audit "$locale" --strict 2>&1)" || rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "[$locale] audit FAILED (exit $rc), not exporting"
    if [[ -n "$out" ]]; then printf '%s\n' "$out" | indent; fi
    return 1
  fi
  # Echo the TOTAL line even on success. "exit 0" alone cannot distinguish a
  # verified locale from one that merely had nothing to verify, and the advisory
  # (en_leak) count is only visible here — run `i18n tasks audit <locale>` for
  # the detail.
  printf '%s\n' "$out" | grep '^TOTAL:' | sed "s/^/[$locale] /" || true
  return 0
}

# Post-export check: placeholder parity in the content just written.
# `validate variables` exits with its BLOCKING COUNT, and exit 1 is ambiguous (it is
# also the "locale not found"/crash path, which prints no JSON). Decide on the
# parsed report, treating an unparseable one as dirty — never as clean.
#
# The report categorizes its own findings and publishes `blocking` — every
# non-advisory category, summed across locales. Read that number and nothing
# else: a gate that post-filters the report has to re-derive the policy (which
# key shapes are metadata, which findings are coverage rather than defects) and
# will eventually re-derive it wrong. That is how #4080 got its shell-side
# METADATA_FIELDS list. A missing `blocking` raises here, which the caller
# treats as an unparseable report — dirty, never clean.
VALIDATE_VARIABLES_COUNT_PY='
import sys, json

print(json.load(sys.stdin)["blocking"])
'

validate_variables() {
  local locale="$1" out count rc=0
  out="$(python3 "$I18N" validate variables --locale "$locale" --json 2>/dev/null)" || rc=$?
  count="$(printf '%s' "$out" \
    | python3 -c "$VALIDATE_VARIABLES_COUNT_PY" 2>/dev/null || true)"
  if ! [[ "$count" =~ ^[0-9]+$ ]]; then
    echo "[$locale] variable validation produced no parseable report (exit $rc)"
    return 1
  fi
  if [[ "$count" -gt 0 ]]; then
    echo "[$locale] $count blocking validation finding(s) in exported content"
    return 1
  fi
  return 0
}

# Post-export check: register (politeness level) lint — same engine as the
# validate-register CI gate. Needs the derived governance cache; when either half
# is missing we say so and pass, because "governance not derived" is not a
# content defect.
register_lint() {
  local locale="$1" out rc=0
  if [[ ! -f "$ROOT/$RULES_LINT_REL" || ! -f "$ROOT/$RESOLVED_DIR_REL/$locale.json" ]]; then
    echo "[$locale] register lint skipped (no $RESOLVED_DIR_REL/$locale.json; run locales/scripts/derive-governance.sh)"
    return 0
  fi
  out="$(cd "$ROOT" && python3 "$RULES_LINT_REL" \
    --resolved "$RESOLVED_DIR_REL/$locale.json" \
    --content-root . \
    "locales/content/$locale/*.json" 2>&1)" || rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "[$locale] register lint FAILED (exit $rc)"
    if [[ -n "$out" ]]; then printf '%s\n' "$out" | indent; fi
    return 1
  fi
  return 0
}

# `exported` counts locales whose content was actually written, dirty or not —
# the summary's job is to describe the working tree, and a locale that exported
# and then failed a validator still changed files on disk.
exported=0
skipped=0
not_drained=()
failed_audit=()
failed_export=()
dirty_locales=()
EXIT_CODE=0

for locale in "${LOCALES[@]}"; do
  pending="$(pending_count "$locale")"

  # Empty means the DB file is missing or the CLI crashed — an unknown locale
  # reports 0 pending. The audit below is the real not-in-DB guard: it fails
  # when zero completed rows were checked, so a content/<locale>/ directory that
  # has never been through `tasks create` cannot preview as ready-to-export.
  if [[ -z "$pending" ]]; then
    echo "[$locale] no task stats (DB missing or CLI failed), skipping"
    ((skipped++)) || true
    continue
  fi

  if [[ "$pending" -ne 0 ]]; then
    echo "[$locale] $pending task(s) still pending, skipping (drain first)"
    not_drained+=("$locale")
    ((skipped++)) || true
    continue
  fi

  echo "[$locale] drained (pending: 0), auditing..."
  if ! audit_locale "$locale"; then
    failed_audit+=("$locale")
    EXIT_CODE=1
    continue
  fi

  echo "[$locale] audit clean, exporting..."
  if $DRY_RUN; then
    echo "  would: i18n tasks export $locale"
    echo "  would: i18n validate variables --locale $locale --json"
    echo "  would: register lint (.translation-rules + $RESOLVED_DIR_REL/$locale.json)"
    ((exported++)) || true
    continue
  fi

  # `tasks export` exits 2 when there is nothing completed to export (e.g. every
  # row skipped). Guard it: under set -e an unguarded call kills the whole run.
  # A failed export wrote nothing, so it is NOT "dirty" — reporting it under
  # "fix the unstaged content" would send the operator after files that do not
  # exist.
  if ! python3 "$I18N" tasks export "$locale"; then
    echo "[$locale] export FAILED"
    failed_export+=("$locale")
    EXIT_CODE=1
    continue
  fi

  # Content is on disk from here on: count it as exported whatever the
  # validators say, then report separately whether it landed clean.
  ((exported++)) || true

  # Post-export validators. Run both (do not short-circuit) so one report names
  # every problem with the locale. Nothing is reverted: the content is unstaged
  # and surfacing it before `git add` is the point.
  locale_dirty=false
  validate_variables "$locale" || locale_dirty=true
  register_lint "$locale" || locale_dirty=true

  if $locale_dirty; then
    dirty_locales+=("$locale")
    EXIT_CODE=1
  fi
done

echo
# Shared tables (glossary, session_log, translation_issues) — once, after locales.
echo "Shared DB tables (glossary + translation_issues + session_log)..."
# Guarded like every other external call: under set -e an unguarded failure here
# would abort before the summary and before `exit $EXIT_CODE`, throwing away the
# per-locale report this script exists to produce.
if $DRY_RUN; then
  echo "  would: i18n db export"
elif ! python3 "$I18N" db export; then
  echo "shared db export FAILED"
  EXIT_CODE=1
fi

echo
verb="exported"
$DRY_RUN && verb="ready to export"
echo "Done: $exported locale(s) $verb, $skipped skipped, ${#failed_audit[@]} failed audit, ${#failed_export[@]} failed export, ${#dirty_locales[@]} dirty"
if [[ ${#not_drained[@]} -gt 0 ]]; then
  echo "Not drained (skipped): ${not_drained[*]}"
fi
if [[ ${#failed_audit[@]} -gt 0 ]]; then
  echo "Failed audit (not exported): ${failed_audit[*]}"
fi
if [[ ${#failed_export[@]} -gt 0 ]]; then
  echo "Export failed (nothing written): ${failed_export[*]}"
fi
if [[ ${#dirty_locales[@]} -gt 0 ]]; then
  echo "Exported but dirty (fix the content, it is unstaged): ${dirty_locales[*]}"
fi
$DRY_RUN && echo "Re-run with --execute to apply."

exit $EXIT_CODE
