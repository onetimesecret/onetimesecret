#!/usr/bin/env bash
# scripts/upgrades/v0.24.0/reset.sh
#
# Resets the v0.24.0 upgrade state so upgrade.sh can be re-run from scratch.
#
# This is a companion to upgrade.sh. It undoes the side-effects of each phase
# so the operator can iterate on the migration without leftover state.
#
#   Phase 1-2 artifacts: JSONL files, logs, checkpoints in DATA_DIR
#   Phase 3 artifacts:   v2 records loaded into target Valkey DB 0
#   Phase 4 artifacts:   _original_* audit keys in target Valkey DB 0
#   Phase 5 artifacts:   Auth SQL database accounts (NOT touched by this script)
#
# By default, only local files are removed. Target Valkey is only flushed
# when --flush-target is explicitly passed. Auth SQL is never touched.
#
# Usage:
#   scripts/upgrades/v0.24.0/reset.sh [OPTIONS]
#
# Options:
#   --flush-target      Flush target Valkey DB 0 (DESTRUCTIVE -- requires confirmation)
#   --flush-originals   Remove only _original_* audit keys from target (less destructive)
#   --keep-dumps        Preserve Phase 1 dump files; only remove transforms + indexes
#   --keep-logs         Preserve log files and checkpoints
#   --data-dir=DIR      Data directory (default: data/upgrades/v0.24.0)
#   --target-url=URL    Target Valkey URL (overrides TARGET_VALKEY_URL env)
#   --timeout=SECS      Redis operation timeout in seconds (default: 30)
#   --yes               Skip confirmation prompts (for scripted use)
#   --dry-run           Show what would be removed without doing it
#   --help              Show this help
#
# Environment:
#   TARGET_VALKEY_URL   Valkey/Redis URL for the v0.24.0 target (DB 0)
#
# Safety:
#   - Idempotent: safe to run multiple times
#   - Never touches the SOURCE Redis (v1 data is read-only throughout)
#   - Never touches Auth SQL -- that requires manual intervention
#   - --flush-target requires interactive confirmation unless --yes is passed
#
# Examples:
#   # Remove local files only (default, safe)
#   scripts/upgrades/v0.24.0/reset.sh
#
#   # Remove local files but keep the original dumps for faster re-run
#   scripts/upgrades/v0.24.0/reset.sh --keep-dumps
#
#   # Full reset: local files + flush target Valkey DB 0
#   TARGET_VALKEY_URL=redis://new-host:6380 \
#     scripts/upgrades/v0.24.0/reset.sh --flush-target
#
#   # Remove only the _original_* audit keys from target
#   TARGET_VALKEY_URL=redis://new-host:6380 \
#     scripts/upgrades/v0.24.0/reset.sh --flush-originals
#
#   # Unattended full reset (CI/staging)
#   scripts/upgrades/v0.24.0/reset.sh --flush-target --yes
#
# See also:
#   scripts/upgrades/v0.24.0/info.sh    -- inspect source/target keyspace (read-only)

set -euo pipefail

# ── Configuration ───────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

FLUSH_TARGET=false
FLUSH_ORIGINALS=false
KEEP_DUMPS=false
KEEP_LOGS=false
DATA_DIR=""
REDIS_TIMEOUT=30
AUTO_YES=false
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --flush-target)     FLUSH_TARGET=true ;;
    --flush-originals)  FLUSH_ORIGINALS=true ;;
    --keep-dumps)       KEEP_DUMPS=true ;;
    --keep-logs)        KEEP_LOGS=true ;;
    --target-url=*)     TARGET_VALKEY_URL="${arg#*=}" ;;
    --data-dir=*)       DATA_DIR="${arg#*=}" ;;
    --timeout=*)        REDIS_TIMEOUT="${arg#*=}" ;;
    --yes|-y)           AUTO_YES=true ;;
    --dry-run)          DRY_RUN=true ;;
    --help|-h)
      awk '/^#!/{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Use --help for usage"
      exit 1
      ;;
  esac
done

DATA_DIR="${DATA_DIR:-data/upgrades/v0.24.0}"

# ── Verify project root ────────────────────────────────────────────────────────

cd "$PROJECT_ROOT"

if [ ! -f "CLAUDE.md" ] || [ ! -d "scripts/upgrades/v0.24.0" ]; then
  echo "FATAL: Script must run from the onetimesecret project root"
  echo "  Expected: $PROJECT_ROOT"
  exit 1
fi

# ── Helpers ─────────────────────────────────────────────────────────────────────

redact_url() {
  echo "$1" | sed -E 's|(://[^:]*:)[^@]*(@)|\1***\2|'
}

confirm() {
  local prompt="$1"
  if $AUTO_YES; then
    echo "  (--yes: proceeding automatically)"
    return 0
  fi
  read -rp "  $prompt [y/N] " response
  case "$response" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

run_or_preview() {
  local description="$1"
  shift
  if $DRY_RUN; then
    echo "  DRY-RUN: $description"
  else
    echo "  $description"
    "$@"
  fi
}

# ── Summary of what will happen ───────────────────────────────────────────────

MODE="EXECUTE"
if $DRY_RUN; then
  MODE="DRY-RUN"
fi

echo ""
echo "+-----------------------------------------------------------------------+"
echo "|  v0.24.0 Reset -- Clean upgrade artifacts for re-run                  |"
echo "+-----------------------------------------------------------------------+"
echo "|"
echo "|  Mode:            $MODE"
echo "|  Data dir:        $DATA_DIR"
if $FLUSH_TARGET || $FLUSH_ORIGINALS; then
  echo "|  Target:          $(redact_url "${TARGET_VALKEY_URL:-<not set>}")"
fi
echo "|"
echo "|  Actions:"
if ! $KEEP_DUMPS; then
  echo "|    - Remove dump files (*_dump.jsonl)"
fi
echo "|    - Remove transform files (*_transformed.jsonl, *_enriched.jsonl)"
echo "|    - Remove index files (*_indexes.jsonl)"
if ! $KEEP_LOGS; then
  echo "|    - Remove logs and checkpoints"
fi
if $FLUSH_TARGET; then
  echo "|    - FLUSH target Valkey DB 0 (DESTRUCTIVE)"
elif $FLUSH_ORIGINALS; then
  echo "|    - Remove _original_* keys from target Valkey DB 0"
fi
echo "|"
echo "|  Preserved:"
if $KEEP_DUMPS; then
  echo "|    - Dump files (*_dump.jsonl) -- for faster re-run"
fi
if $KEEP_LOGS; then
  echo "|    - Log files and checkpoints"
fi
echo "|    - Source Redis (never modified)"
echo "|    - Auth SQL database (never modified by this script)"
echo "|"
echo "+-----------------------------------------------------------------------+"
echo ""

# ── Phase 1-2: Clean local filesystem artifacts ────────────────────────────────

echo "=== Local filesystem cleanup ==="
echo ""

if [ ! -d "$DATA_DIR" ]; then
  echo "  Data directory does not exist: $DATA_DIR"
  echo "  Nothing to clean locally."
else
  # Only dumps and logs need pre-counted (they have --keep-* flags)
  DUMP_COUNT=$(find "$DATA_DIR" -name '*_dump.jsonl' 2>/dev/null | wc -l | tr -d ' ')
  LOG_COUNT=$(find "$DATA_DIR" -path '*/logs/*' 2>/dev/null | wc -l | tr -d ' ')

  TOTAL_REMOVE=0

  # Remove enriched, transform, and index files (always)
  for pattern_label in \
    '*_enriched.jsonl:enriched' \
    '*_transformed.jsonl:transform' \
    '*_indexes.jsonl:index'; do
    pattern="${pattern_label%%:*}"
    label="${pattern_label##*:}"
    count=$(find "$DATA_DIR" -name "$pattern" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$count" -gt 0 ]; then
      run_or_preview "Removing $count $label file(s)" \
        find "$DATA_DIR" -name "$pattern" -delete 2>/dev/null || true
      TOTAL_REMOVE=$((TOTAL_REMOVE + count))
    fi
  done

  # Remove dump files (unless --keep-dumps)
  if ! $KEEP_DUMPS && [ "$DUMP_COUNT" -gt 0 ]; then
    run_or_preview "Removing $DUMP_COUNT dump file(s)" \
      find "$DATA_DIR" -name '*_dump.jsonl' -delete 2>/dev/null || true
    TOTAL_REMOVE=$((TOTAL_REMOVE + DUMP_COUNT))
  elif $KEEP_DUMPS && [ "$DUMP_COUNT" -gt 0 ]; then
    echo "  Keeping $DUMP_COUNT dump file(s) (--keep-dumps)"
  fi

  # Remove logs and checkpoints (unless --keep-logs)
  if ! $KEEP_LOGS && [ "$LOG_COUNT" -gt 0 ]; then
    run_or_preview "Removing logs and checkpoints" \
      rm -rf "${DATA_DIR}/logs" 2>/dev/null || true
    TOTAL_REMOVE=$((TOTAL_REMOVE + LOG_COUNT))
  elif $KEEP_LOGS && [ "$LOG_COUNT" -gt 0 ]; then
    echo "  Keeping logs (--keep-logs)"
  fi

  # Clean up empty model subdirectories
  if ! $DRY_RUN; then
    find "$DATA_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null || true
  fi

  echo ""
  if [ "$TOTAL_REMOVE" -gt 0 ]; then
    echo "  Removed $TOTAL_REMOVE file(s)"
  else
    echo "  No files to remove"
  fi
fi

echo ""

# ── Phase 3-4: Clean target Valkey ──────────────────────────────────────────────

if $FLUSH_TARGET; then
  echo "=== Target Valkey: FLUSH DB 0 ==="
  echo ""

  if [ -z "${TARGET_VALKEY_URL:-}" ]; then
    echo "  FATAL: --flush-target requires TARGET_VALKEY_URL"
    echo "  Set via environment variable or --target-url=URL"
    exit 1
  fi

  # Validate connectivity
  echo -n "  Connecting to target: "
  if ! DBSIZE=$(ruby -e "
    require 'redis'
    require 'uri'
    u = URI.parse(ARGV[0]); u.path = '/0'
    r = Redis.new(url: u.to_s, timeout: ARGV[1].to_i)
    r.ping
    puts r.dbsize
  " "$TARGET_VALKEY_URL" "$REDIS_TIMEOUT" 2>/dev/null); then
    echo "FAILED"
    echo "  FATAL: Cannot connect to target at $(redact_url "$TARGET_VALKEY_URL")"
    exit 1
  fi
  echo "OK ($DBSIZE keys in DB 0)"

  if [ "$DBSIZE" = "0" ]; then
    echo "  Target DB 0 is already empty. Nothing to flush."
  else
    echo ""
    echo "  WARNING: This will DELETE ALL $DBSIZE keys in target DB 0."
    echo "  Target: $(redact_url "$TARGET_VALKEY_URL")"
    echo ""

    if confirm "Flush target Valkey DB 0? This cannot be undone."; then
      if $DRY_RUN; then
        echo "  DRY-RUN: Would flush DB 0 ($DBSIZE keys)"
      else
        ruby -e "
          require 'redis'
          require 'uri'
          u = URI.parse(ARGV[0]); u.path = '/0'
          r = Redis.new(url: u.to_s, timeout: ARGV[1].to_i)
          r.flushdb
          puts '  Flushed DB 0'
        " "$TARGET_VALKEY_URL" "$REDIS_TIMEOUT"
      fi
    else
      echo "  Skipped -- target DB 0 not flushed."
    fi
  fi

  echo ""

elif $FLUSH_ORIGINALS; then
  echo "=== Target Valkey: Remove _original_* keys ==="
  echo ""

  if [ -z "${TARGET_VALKEY_URL:-}" ]; then
    echo "  FATAL: --flush-originals requires TARGET_VALKEY_URL"
    echo "  Set via environment variable or --target-url=URL"
    exit 1
  fi

  # Validate connectivity
  echo -n "  Connecting to target: "
  if ! ruby -e "
    require 'redis'
    require 'uri'
    u = URI.parse(ARGV[0]); u.path = '/0'
    r = Redis.new(url: u.to_s, timeout: ARGV[1].to_i)
    r.ping
  " "$TARGET_VALKEY_URL" "$REDIS_TIMEOUT" 2>/dev/null; then
    echo "FAILED"
    echo "  FATAL: Cannot connect to target at $(redact_url "$TARGET_VALKEY_URL")"
    exit 1
  fi
  echo "OK"

  # Count _original_* keys first
  ORIG_COUNT=$(ruby -e "
    require 'redis'
    require 'uri'
    u = URI.parse(ARGV[0]); u.path = '/0'
    r = Redis.new(url: u.to_s, timeout: ARGV[1].to_i)
    count = 0
    r.scan_each(match: '*:_original_*') { count += 1 }
    puts count
  " "$TARGET_VALKEY_URL" "$REDIS_TIMEOUT" 2>/dev/null || echo "0")

  echo "  Found $ORIG_COUNT _original_* keys in DB 0"

  if [ "$ORIG_COUNT" = "0" ]; then
    echo "  Nothing to remove."
  else
    echo ""
    if confirm "Remove $ORIG_COUNT _original_* audit keys?"; then
      if $DRY_RUN; then
        echo "  DRY-RUN: Would remove $ORIG_COUNT _original_* keys"
      else
        DELETED=$(ruby -e "
          require 'redis'
          require 'uri'
          u = URI.parse(ARGV[0]); u.path = '/0'
          r = Redis.new(url: u.to_s, timeout: ARGV[1].to_i)
          deleted = 0
          batch = []
          r.scan_each(match: '*:_original_*') do |key|
            batch << key
            if batch.size >= 100
              r.del(*batch)
              deleted += batch.size
              batch.clear
            end
          end
          r.del(*batch) unless batch.empty?
          deleted += batch.size
          puts deleted
        " "$TARGET_VALKEY_URL" "$REDIS_TIMEOUT")
        echo "  Removed $DELETED _original_* keys"
      fi
    else
      echo "  Skipped -- _original_* keys preserved."
    fi
  fi

  echo ""
fi

# ── Reminder: target DB 0 ─────────────────────────────────────────────────────

if ! $FLUSH_TARGET && ! $FLUSH_ORIGINALS && [ -n "${TARGET_VALKEY_URL:-}" ]; then
  TARGET_DBSIZE=$(ruby -e "
    require 'redis'
    require 'uri'
    u = URI.parse(ARGV[0]); u.path = '/0'
    r = Redis.new(url: u.to_s, timeout: ARGV[1].to_i)
    puts r.dbsize
  " "$TARGET_VALKEY_URL" "$REDIS_TIMEOUT" 2>/dev/null || echo "unknown")

  if [ "$TARGET_DBSIZE" != "0" ] && [ "$TARGET_DBSIZE" != "unknown" ]; then
    echo ""
    echo "  NOTE: Target Valkey DB 0 still contains $TARGET_DBSIZE keys."
    echo "  For a clean re-run, add --flush-target to also flush DB 0."
    echo ""
  fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────

if $DRY_RUN; then
  echo "Done (dry-run). Re-run without --dry-run to perform the reset."
else
  echo "Done. Removed $TOTAL_REMOVE file(s)."
fi
