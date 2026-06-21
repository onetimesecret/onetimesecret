#!/usr/bin/env bash
#
# Deterministic mechanics for the review-locale-branches workflow.
#
# This script is the single source of truth for the family->locales mapping
# and the non-agent (deterministic) stages of the locale-branch review:
#   - Stage 1 variable validation  (subcommand: validate)
#   - Stage 3 group consolidation   (subcommand: consolidate)
# The agent orchestration and triage stages live in the slash command
# (locales/slash_commands/review-locale-branches.md), which calls this script.
#
# Usage:
#   locales/scripts/review-locale-branches.sh validate [RESULTS_DIR]
#   locales/scripts/review-locale-branches.sh consolidate REVIEW_DIR
#   locales/scripts/review-locale-branches.sh init REVIEW_DIR
#   locales/scripts/review-locale-branches.sh families

set -euo pipefail

# ---------------------------------------------------------------------------
# Family -> locales mapping (authoritative; used by consolidate and families)
# ---------------------------------------------------------------------------
# Ordered list of family group names, and a lookup from group -> space-
# separated locale list. Keep these in sync with the table in the slash
# command (review-locale-branches.md).

FAMILY_GROUPS=(semitic-rtl slavic germanic romance cjk other)

declare -A FAMILY_LOCALES=(
  [semitic-rtl]="ar he"
  [slavic]="bg cs pl ru sl_SI uk"
  [germanic]="de de_AT nl sv_SE"
  [romance]="ca_ES es fr_CA fr_FR it_IT pt_BR pt_PT"
  [cjk]="ja ko zh"
  [other]="da_DK el_GR eo hu mi_NZ tr vi"
)

die() { echo "error: $1" >&2; exit 1; }

# ---------------------------------------------------------------------------
# families: print the family->locales mapping, one group per line.
# ---------------------------------------------------------------------------
cmd_families() {
  for group in "${FAMILY_GROUPS[@]}"; do
    printf '%s: %s\n' "$group" "${FAMILY_LOCALES[$group]}"
  done
}

# ---------------------------------------------------------------------------
# init REVIEW_DIR: create the review output directory.
# ---------------------------------------------------------------------------
cmd_init() {
  local review_dir="${1:-}"
  [[ -n "$review_dir" ]] || die "init requires REVIEW_DIR"
  mkdir -p "$review_dir"
}

# ---------------------------------------------------------------------------
# validate [RESULTS_DIR]: Stage 1.
# For each i18n/update-* branch, run variable validation with --json, write
# the JSON to RESULTS_DIR, and print one line per locale whose total mismatch
# count is > 0. Always exits 0 (this is a report, not a gate).
# ---------------------------------------------------------------------------
cmd_validate() {
  local results_dir="${1:-/tmp}"
  mkdir -p "$results_dir"

  for branch in $(git branch --list 'i18n/update-*' | tr -d ' ' | sed 's/\x1b\[[0-9;]*m//g'); do
    local locale="${branch#i18n/update-}"
    local out="${results_dir}/i18n-validate-${locale}.json"
    python3 locales/scripts/i18n validate variables --json --locale "$locale" > "$out"
    local count
    count=$(jq '.summary | to_entries | map(.value) | add // 0' "$out")
    if [ "$count" -gt 0 ]; then
      echo "$locale: $count variable mismatches — $out"
    fi
  done

  return 0
}

# ---------------------------------------------------------------------------
# consolidate REVIEW_DIR: Stage 3.
# For each family group, write ${REVIEW_DIR}/${group}.md by concatenating the
# per-locale ${REVIEW_DIR}/${loc}.md files that exist.
# ---------------------------------------------------------------------------
cmd_consolidate() {
  local review_dir="${1:-}"
  [[ -n "$review_dir" ]] || die "consolidate requires REVIEW_DIR"

  local review_date
  review_date=$(basename "$review_dir")

  for group in "${FAMILY_GROUPS[@]}"; do
    local locales="${FAMILY_LOCALES[$group]}"
    local group_file="${review_dir}/${group}.md"

    echo "# ${group} Group Review - ${review_date}" > "$group_file"
    echo "" >> "$group_file"
    echo "Locales: ${locales}" >> "$group_file"
    echo "" >> "$group_file"

    for loc in $locales; do
      if [ -f "${review_dir}/${loc}.md" ]; then
        echo "---" >> "$group_file"
        cat "${review_dir}/${loc}.md" >> "$group_file"
        echo "" >> "$group_file"
      fi
    done
  done
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
main() {
  local cmd="${1:-}"
  [[ -n "$cmd" ]] || die "usage: $(basename "$0") {validate|consolidate|init|families} [args]"
  shift

  case "$cmd" in
    validate)    cmd_validate "$@" ;;
    consolidate) cmd_consolidate "$@" ;;
    init)        cmd_init "$@" ;;
    families)    cmd_families "$@" ;;
    *)           die "unknown subcommand: $cmd" ;;
  esac
}

main "$@"
