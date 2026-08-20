#!/usr/bin/env bash
#
# Populate the translation tasks DB for every current locale.
#
# "Current locales" = every directory under locales/content/ except the English
# source (en). For each, runs `i18n tasks create LOCALE`, which enqueues one task
# per English level — but only the keys that still need work: missing
# (untranslated) plus stale (en changed after the translation was made).
# Reviewed, still-current translations are never re-enqueued, so a locale that is
# already caught up produces no tasks at all. Pass nothing to get that; `tasks
# create --all` (target-blind, full re-translation) is deliberately not used here.
#
# Re-running is safe for in-flight work (pending rows get refreshed keys,
# in_progress/skipped rows keep their status) but NOT a no-op for drained
# levels: a completed row that still has work is REOPENED — status back to
# pending, its translations discarded. That is free once the text has been
# exported to content/, so the routine catch-up needs no ceremony.
#
# A locale holding completed-but-NEVER-exported translations is instead BLOCKED:
# `tasks create --apply` exits 3 and writes nothing for it. This script keeps
# going, processes every other locale, lists the blocked ones at the end, and
# exits non-zero. Resolve each with `i18n tasks export LOCALE` (keeps the work)
# or `i18n tasks create LOCALE --apply --reopen` (discards it) — deliberately
# per-locale, since discarding work in bulk should never be one flag away.
#
# By default this SKIPS locales that already have tasks (so the locales currently
# being translated are left untouched). Use --force to (re)generate for every
# locale, including populated ones.
#
# No environment setup needed (the project uses direnv/.envrc); the task scripts
# resolve paths relative to the repo. Run from anywhere in the repo.
#
# Usage:
#   locales/scripts/create-all.sh            # populate locales with no tasks yet
#   locales/scripts/create-all.sh --force    # (re)generate for ALL locales
#   locales/scripts/create-all.sh --dry-run  # preview, write nothing
#
# Note: --force issues writes against tasks.db; avoid it while translation agents
# are actively draining the queue (run it when idle).

set -euo pipefail

FORCE=0
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --force)   FORCE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      # Print the leading comment block (skip shebang, stop at first non-comment line).
      awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--force] [--dry-run]" >&2
      exit 2
      ;;
  esac
done

cd "$(git rev-parse --show-toplevel)"

CONTENT_DIR="locales/content"
DB_FILE="locales/db/tasks.db"
SKIP_LOCALE="en"  # English is the source, not a translation target

if [ ! -f "$DB_FILE" ]; then
  echo "Error: $DB_FILE not found. Initialize it first (see locales/TRANSLATION_PROTOCOL.md)." >&2
  exit 1
fi

# Enable WAL once so concurrent readers/writers don't block (idempotent, persists).
if [ "$DRY_RUN" -eq 0 ]; then
  sqlite3 "$DB_FILE" "PRAGMA journal_mode=WAL;" >/dev/null
fi

# Discover current locales from content/ (excluding the English source).
locales=()
while IFS= read -r dir; do
  name="$(basename "$dir")"
  [ "$name" = "$SKIP_LOCALE" ] && continue
  locales+=("$name")
done < <(find "$CONTENT_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

echo "Found ${#locales[@]} locale(s) under $CONTENT_DIR (excluding '$SKIP_LOCALE')."
echo

created=0
skipped=0
blocked=()
for locale in "${locales[@]}"; do
  existing="$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM translation_tasks WHERE locale='$locale';")"

  if [ "$FORCE" -eq 0 ] && [ "$existing" -gt 0 ]; then
    echo "-- $locale: already has $existing task(s), skipping (use --force to regenerate)"
    skipped=$((skipped + 1))
    continue
  fi

  echo "== $locale: generating tasks (existing: $existing) =="
  # `|| status=$?` keeps `set -e` from aborting the batch on a per-locale
  # failure: one blocked locale must not strand every locale after it. The
  # refusal message goes to stderr, so `tail` (stdout only) never hides it.
  status=0
  if [ "$DRY_RUN" -eq 1 ]; then
    python3 locales/scripts/i18n tasks create "$locale" | tail -4 || status=$?
  else
    python3 locales/scripts/i18n tasks create "$locale" --apply | tail -4 || status=$?
  fi

  case "$status" in
    0) created=$((created + 1)) ;;
    3)
      # Refused: unexported translations would have been discarded. Nothing was
      # written for this locale; the operator decides its fate individually.
      blocked+=("$locale")
      ;;
    *)
      echo "Error: tasks create failed for '$locale' (exit $status)." >&2
      exit "$status"
      ;;
  esac
  echo
done

echo "Done. Generated/refreshed: $created  |  skipped (already populated): $skipped  |  blocked: ${#blocked[@]}"

if [ "${#blocked[@]}" -gt 0 ]; then
  echo
  echo "=== BLOCKED: unexported translations would have been discarded ==="
  for locale in "${blocked[@]}"; do
    echo "  $locale"
    echo "    keep:    python3 locales/scripts/i18n tasks export $locale"
    echo "    discard: python3 locales/scripts/i18n tasks create $locale --apply --reopen"
  done
fi

if [ "$DRY_RUN" -eq 0 ]; then
  echo
  echo "=== Task counts per locale ==="
  sqlite3 "$DB_FILE" \
    "SELECT locale,
            SUM(status='completed') AS completed,
            SUM(status='pending')   AS pending,
            COUNT(*)                AS total
     FROM translation_tasks GROUP BY locale ORDER BY locale;" -header -column
fi

# Non-zero when any locale was refused, so CI and orchestrators notice that the
# batch is incomplete. Every other locale was still processed.
if [ "${#blocked[@]}" -gt 0 ]; then
  exit 1
fi
