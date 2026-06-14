#!/usr/bin/env bash
#
# Populate the translation tasks DB for every current locale.
#
# "Current locales" = every directory under locales/content/ except the English
# source (en). For each, runs `i18n tasks create LOCALE`, which mirrors the full
# English level structure into the translation_tasks table (one task per level).
#
# Safe to re-run: `tasks create` upserts via ON CONFLICT(file, level_path, locale)
# and only refreshes keys_json + updated_at — it never touches `status` or
# `translations_json`, so in-flight / completed work is preserved.
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
for locale in "${locales[@]}"; do
  existing="$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM translation_tasks WHERE locale='$locale';")"

  if [ "$FORCE" -eq 0 ] && [ "$existing" -gt 0 ]; then
    echo "-- $locale: already has $existing task(s), skipping (use --force to regenerate)"
    skipped=$((skipped + 1))
    continue
  fi

  echo "== $locale: generating tasks (existing: $existing) =="
  if [ "$DRY_RUN" -eq 1 ]; then
    python3 locales/scripts/i18n tasks create "$locale" --dry-run | tail -4
  else
    python3 locales/scripts/i18n tasks create "$locale" | tail -4
  fi
  created=$((created + 1))
  echo
done

echo "Done. Generated/refreshed: $created  |  skipped (already populated): $skipped"

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
