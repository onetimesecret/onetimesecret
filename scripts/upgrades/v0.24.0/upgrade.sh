#!/usr/bin/env bash
# scripts/upgrades/v0.24.0/upgrade.sh
#
# Orchestrates the full v0.24.0 data migration (Familia v1 -> v2).
#
#   Phase 1: Dump keys from source Redis (multi-DB) to JSONL files
#   Phase 2: Run transform pipeline (enrich, transform, validate)
#   Phase 3: Load transformed data into target Valkey (DB 0)
#   Phase 4: Archive original v1 records in target (30-day TTL)
#   Phase 5: Sync customer accounts to Auth SQL database
#
# Pre-upgrade backups and recovery are handled outside this script.
#
# Usage:
#   scripts/upgrades/v0.24.0/upgrade.sh [OPTIONS]
#
# Options:
#   --execute           Perform the migration (default: dry-run preview)
#   --start-phase=N     Resume from phase N (1-5, default: 1)
#   --skip-gates        Skip interactive confirmation between phases
#   --source-url=URL    Source Redis URL (overrides SOURCE_REDIS_URL env)
#   --target-url=URL    Target Valkey URL (overrides TARGET_VALKEY_URL env)
#   --data-dir=DIR      Data directory (default: data/upgrades/v0.24.0)
#   --timeout=SECS      Redis operation timeout in seconds (default: 30)
#   --help              Show this help
#
# Environment:
#   SOURCE_REDIS_URL    Redis URL for the v0.23.x source (reads DBs 6,7,8,11)
#   TARGET_VALKEY_URL   Valkey/Redis URL for the v0.24.0 target (writes DB 0)
#
# Both URLs are REQUIRED. There is no fallback to REDIS_URL or VALKEY_URL.
# This is intentional -- the operator must be explicit about source vs target.
#
# Examples:
#   # Dry-run (default) -- preview what would happen
#   SOURCE_REDIS_URL=redis://old-host:6379 \
#   TARGET_VALKEY_URL=redis://new-host:6380 \
#     scripts/upgrades/v0.24.0/upgrade.sh
#
#   # Execute the migration
#   SOURCE_REDIS_URL=redis://old-host:6379 \
#   TARGET_VALKEY_URL=redis://new-host:6380 \
#     scripts/upgrades/v0.24.0/upgrade.sh --execute
#
#   # Resume from phase 3 after inspecting phase 2 output
#   scripts/upgrades/v0.24.0/upgrade.sh --execute --start-phase=3
#
#   # Unattended run (CI/staging)
#   scripts/upgrades/v0.24.0/upgrade.sh --execute --skip-gates

set -euo pipefail

# ── Configuration ───────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

EXECUTE=false
START_PHASE=1
SKIP_GATES=false
DATA_DIR=""
REDIS_TIMEOUT=30

for arg in "$@"; do
  case "$arg" in
    --execute)        EXECUTE=true ;;
    --start-phase=*)  START_PHASE="${arg#*=}" ;;
    --skip-gates)     SKIP_GATES=true ;;
    --source-url=*)   SOURCE_REDIS_URL="${arg#*=}" ;;
    --target-url=*)   TARGET_VALKEY_URL="${arg#*=}" ;;
    --data-dir=*)     DATA_DIR="${arg#*=}" ;;
    --timeout=*)      REDIS_TIMEOUT="${arg#*=}" ;;
    --help|-h)
      sed -n '2,/^[^#]/{ /^#/s/^# \?//p }' "${BASH_SOURCE[0]}"
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
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_DIR="${DATA_DIR}/logs"
LOG_FILE="${LOG_DIR}/upgrade_${TIMESTAMP}.log"

# ── Verify project root ────────────────────────────────────────────────────────

cd "$PROJECT_ROOT"

if [ ! -f "CLAUDE.md" ] || [ ! -d "scripts/upgrades/v0.24.0" ]; then
  echo "FATAL: Script must run from the onetimesecret project root"
  echo "  Expected: $PROJECT_ROOT"
  exit 1
fi

# ── Logging ─────────────────────────────────────────────────────────────────────

mkdir -p "$LOG_DIR"

# Duplicate all output to timestamped log file
exec > >(while IFS= read -r line; do
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$line"
done | tee -a "$LOG_FILE") 2>&1

log_phase() {
  local phase="$1" description="$2"
  echo ""
  echo "======================================================================="
  echo "  Phase $phase: $description"
  echo "======================================================================="
  echo ""
}

# ── Signal handling ─────────────────────────────────────────────────────────────

CURRENT_PHASE=0

cleanup_on_signal() {
  local sig="$1"
  echo ""
  echo "-----------------------------------------------------------------------"
  echo "  INTERRUPTED by $sig during Phase $CURRENT_PHASE"
  echo ""
  echo "  To resume: $0 --execute --start-phase=$CURRENT_PHASE"
  echo "  Log file:  $LOG_FILE"
  echo "-----------------------------------------------------------------------"

  # Write checkpoint for resumption
  cat > "${LOG_DIR}/checkpoint_${TIMESTAMP}.json" <<CHECKPOINT
{
  "interrupted_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "signal": "$sig",
  "phase": $CURRENT_PHASE,
  "mode": "$MODE",
  "resume_command": "$0 --execute --start-phase=$CURRENT_PHASE",
  "log_file": "$LOG_FILE"
}
CHECKPOINT

  exit 130
}

trap 'cleanup_on_signal SIGINT' INT
trap 'cleanup_on_signal SIGTERM' TERM

# ── Validate URLs ───────────────────────────────────────────────────────────────

if [ -z "${SOURCE_REDIS_URL:-}" ]; then
  echo "FATAL: SOURCE_REDIS_URL is required"
  echo ""
  echo "  Set via environment variable or --source-url=URL"
  echo "  This is the v0.23.x Redis instance to read from (DBs 6, 7, 8, 11)"
  exit 1
fi

if [ -z "${TARGET_VALKEY_URL:-}" ]; then
  echo "FATAL: TARGET_VALKEY_URL is required"
  echo ""
  echo "  Set via environment variable or --target-url=URL"
  echo "  This is the v0.24.0 Valkey/Redis instance to write to (DB 0)"
  exit 1
fi

# Redact passwords for display
redact_url() {
  echo "$1" | sed -E 's|(://[^:]*:)[^@]*(@)|\1***\2|'
}

# ── Pre-flight checks ──────────────────────────────────────────────────────────

MODE="DRY-RUN"
if $EXECUTE; then
  MODE="EXECUTE"
fi

echo ""
echo "+-----------------------------------------------------------------------+"
echo "|  v0.24.0 Upgrade -- Familia v1 -> v2 Data Migration                   |"
echo "+-----------------------------------------------------------------------+"
echo "|"
echo "|  Mode:       $MODE"
echo "|  Source:     $(redact_url "$SOURCE_REDIS_URL")"
echo "|  Target:     $(redact_url "$TARGET_VALKEY_URL")"
echo "|  Data dir:   $DATA_DIR"
echo "|  Log file:   $LOG_FILE"
echo "|  Start:      Phase $START_PHASE"
echo "|  Timeout:    ${REDIS_TIMEOUT}s"
echo "|  Timestamp:  $TIMESTAMP"
echo "|"
echo "+-----------------------------------------------------------------------+"
echo ""

# Validate connectivity
echo "Validating connections..."

echo -n "  Source Redis: "
if ! ruby -e "
  require 'redis'
  r = Redis.new(url: ARGV[0], timeout: ARGV[1].to_i)
  r.ping
  puts \"OK (#{r.info['redis_version']})\"
" "$SOURCE_REDIS_URL" "$REDIS_TIMEOUT" 2>/dev/null; then
  echo "FAILED"
  echo "FATAL: Cannot connect to source Redis at $(redact_url "$SOURCE_REDIS_URL")"
  exit 1
fi

echo -n "  Target Valkey: "
if ! ruby -e "
  require 'redis'
  r = Redis.new(url: ARGV[0], timeout: ARGV[1].to_i)
  r.ping
  puts \"OK (#{r.info['redis_version']})\"
" "$TARGET_VALKEY_URL" "$REDIS_TIMEOUT" 2>/dev/null; then
  echo "FAILED"
  echo "FATAL: Cannot connect to target Valkey at $(redact_url "$TARGET_VALKEY_URL")"
  exit 1
fi

# Safety check: warn if source and target resolve to the same host:port
SOURCE_HOST=$(ruby -e "require 'uri'; u = URI.parse(ARGV[0]); puts \"#{u.host}:#{u.port}\"" "$SOURCE_REDIS_URL" 2>/dev/null || echo "unknown")
TARGET_HOST=$(ruby -e "require 'uri'; u = URI.parse(ARGV[0]); puts \"#{u.host}:#{u.port}\"" "$TARGET_VALKEY_URL" 2>/dev/null || echo "unknown")

if [ "$SOURCE_HOST" = "$TARGET_HOST" ]; then
  echo ""
  echo "  WARNING: Source and target resolve to the same host ($SOURCE_HOST)"
  echo "  This is valid for in-place migration (v1 uses DBs 6-11, v2 uses DB 0)"
  echo "  but verify you have backups before proceeding."
  echo ""
fi

# Disk space check (advisory)
if $EXECUTE && [ "$START_PHASE" -le 1 ]; then
  AVAIL_MB=$(df -m "$DATA_DIR" 2>/dev/null | awk 'NR==2{print $4}' || echo "0")
  if [ "$AVAIL_MB" -lt 1024 ] 2>/dev/null; then
    echo ""
    echo "  WARNING: Less than 1 GB available on the data partition ($AVAIL_MB MB)"
    echo "  Large keyspaces may require several GB for JSONL dump files."
    echo ""
  fi
fi

echo ""

# ── Phase gate helper ───────────────────────────────────────────────────────────

confirm_gate() {
  local phase="$1" description="$2"

  if $SKIP_GATES; then
    echo "  (--skip-gates: proceeding automatically)"
    return 0
  fi

  echo ""
  echo "-----------------------------------------------------------------------"
  echo "  Phase $phase complete: $description"
  echo ""
  echo "  Inspect the output above and files in $DATA_DIR/"
  echo "  before continuing to the next phase."
  echo ""

  read -rp "  Continue to next phase? [y/N] " response
  case "$response" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *)
      echo ""
      echo "  Upgrade paused at gate $phase."
      echo "  To resume: $0 --execute --start-phase=$((phase + 1))"
      exit 0
      ;;
  esac
}

DRY_RUN_FLAG=""
if ! $EXECUTE; then
  DRY_RUN_FLAG="--dry-run"
fi

PIPELINE_START=$SECONDS

# ── Phase 1: Dump ──────────────────────────────────────────────────────────────

if [ "$START_PHASE" -le 1 ]; then
  CURRENT_PHASE=1
  log_phase 1 "Dump keys from source Redis to JSONL"

  phase_start=$SECONDS

  ruby scripts/upgrades/v0.24.0/dump_keys.rb \
    --all \
    --redis-url="$SOURCE_REDIS_URL" \
    --output-dir="$DATA_DIR" \
    $DRY_RUN_FLAG

  echo ""
  echo "  Phase 1 completed in $((SECONDS - phase_start))s"

  # Show dump file sizes for operator review
  if $EXECUTE && [ -d "$DATA_DIR" ]; then
    echo ""
    echo "  Dump files:"
    find "$DATA_DIR" -name '*_dump.jsonl' -exec ls -lh {} \; 2>/dev/null | \
      awk '{printf "    %-8s %s\n", $5, $NF}'
  fi

  confirm_gate 1 "Source data dumped to JSONL"
fi

# ── Phase 2: Transform pipeline ────────────────────────────────────────────────
#
# IMPORTANT: run_pipeline.sh validators and transforms need to decode v1 dump
# blobs. They connect to Redis to RESTORE temporarily and read fields. This
# must point at the SOURCE (which has v1 data), not the target (which is empty).
#
# NOTE: run_pipeline.sh also calls enrich_with_original_record.rb which writes
# to Redis. That step belongs in Phase 4 (after load). If you have not yet
# removed that call from run_pipeline.sh, Phase 2 will write _original_* keys
# to the SOURCE Redis. Phase 4 will write them correctly to the TARGET.
# See C1 in the QA review for details.

if [ "$START_PHASE" -le 2 ]; then
  CURRENT_PHASE=2
  log_phase 2 "Run transform pipeline (enrich, transform, validate)"

  phase_start=$SECONDS

  if $EXECUTE; then
    # Point run_pipeline.sh at SOURCE for reading v1 data.
    # run_pipeline.sh reads ${VALKEY_URL:-$REDIS_URL} internally.
    VALKEY_URL="$SOURCE_REDIS_URL" \
      bash scripts/upgrades/v0.24.0/run_pipeline.sh
  else
    echo "  DRY-RUN: Would execute run_pipeline.sh with these steps:"
    echo "    1. enrich_with_identifiers.rb   (file transform, no Redis)"
    echo "    2. 01-customer/transform.rb     (reads source for DUMP decode)"
    echo "       01-customer/create_indexes.rb"
    echo "       01-customer/validate_instance_index.rb"
    echo "    3. 02-organization/generate.rb"
    echo "       02-organization/create_indexes.rb"
    echo "       02-organization/validate_instance_index.rb"
    echo "    4. 03-customdomain/transform.rb"
    echo "       03-customdomain/create_indexes.rb"
    echo "       03-customdomain/validate_instance_index.rb"
    echo "    5. 04-receipt/transform.rb"
    echo "       04-receipt/create_indexes.rb"
    echo "       04-receipt/validate_instance_index.rb"
    echo "    6. 05-secret/transform.rb"
    echo "       05-secret/create_indexes.rb"
    echo "       05-secret/validate_instance_index.rb"
    echo ""
    echo "  Source Redis for decode: $(redact_url "$SOURCE_REDIS_URL")"
  fi

  echo ""
  echo "  Phase 2 completed in $((SECONDS - phase_start))s"

  # Show transformed + index file sizes
  if $EXECUTE && [ -d "$DATA_DIR" ]; then
    echo ""
    echo "  Transformed files:"
    find "$DATA_DIR" -name '*_transformed.jsonl' -exec ls -lh {} \; 2>/dev/null | \
      awk '{printf "    %-8s %s\n", $5, $NF}'
    echo ""
    echo "  Index files:"
    find "$DATA_DIR" -name '*_indexes.jsonl' -exec ls -lh {} \; 2>/dev/null | \
      awk '{printf "    %-8s %s\n", $5, $NF}'
  fi

  confirm_gate 2 "Transforms and validation complete"
fi

# ── Phase 3: Load ──────────────────────────────────────────────────────────────
#
# load_keys.rb uses RESTORE with replace:true. This means existing keys in
# the target will be silently overwritten. The DBSIZE check below helps the
# operator catch accidental double-loads or wrong-target mistakes.

if [ "$START_PHASE" -le 3 ]; then
  CURRENT_PHASE=3
  log_phase 3 "Load transformed data into target Valkey"

  phase_start=$SECONDS

  # Pre-load check: is the target DB 0 empty?
  TARGET_DBSIZE=$(ruby -e "
    require 'redis'
    require 'uri'
    u = URI.parse(ARGV[0]); u.path = '/0'
    r = Redis.new(url: u.to_s, timeout: ARGV[1].to_i)
    puts r.dbsize
  " "$TARGET_VALKEY_URL" "$REDIS_TIMEOUT" 2>/dev/null || echo "unknown")

  echo "  Target DB 0 current key count: $TARGET_DBSIZE"

  if [ "$TARGET_DBSIZE" != "0" ] && [ "$TARGET_DBSIZE" != "unknown" ]; then
    echo ""
    echo "  WARNING: Target DB 0 is not empty ($TARGET_DBSIZE keys)."
    echo "  load_keys.rb uses RESTORE REPLACE -- existing keys will be overwritten."
    echo "  Index commands (ZADD, HSET, SADD) will merge additively."
    echo ""
    if ! $SKIP_GATES; then
      read -rp "  Continue loading into non-empty target? [y/N] " response
      case "$response" in
        [yY]|[yY][eE][sS]) ;;
        *)
          echo "  Aborted. Clear the target or re-run with confirmation."
          exit 0
          ;;
      esac
    fi
  fi

  # Capture keyspace before load
  echo ""
  echo "  Target keyspace BEFORE load:"
  ruby -e "
    require 'redis'
    r = Redis.new(url: ARGV[0], timeout: ARGV[1].to_i)
    info = r.info('keyspace')
    if info.empty?
      puts '    (empty)'
    else
      info.each { |db, stats| puts \"    #{db}: #{stats}\" }
    end
  " "$TARGET_VALKEY_URL" "$REDIS_TIMEOUT" 2>/dev/null || echo "    (could not read keyspace)"
  echo ""

  ruby scripts/upgrades/v0.24.0/load_keys.rb \
    --valkey-url="$TARGET_VALKEY_URL" \
    --input-dir="$DATA_DIR" \
    $DRY_RUN_FLAG

  # Capture keyspace after load
  if $EXECUTE; then
    echo ""
    echo "  Target keyspace AFTER load:"
    ruby -e "
      require 'redis'
      r = Redis.new(url: ARGV[0], timeout: ARGV[1].to_i)
      info = r.info('keyspace')
      info.each { |db, stats| puts \"    #{db}: #{stats}\" }
    " "$TARGET_VALKEY_URL" "$REDIS_TIMEOUT" 2>/dev/null || echo "    (could not read keyspace)"
  fi

  echo ""
  echo "  Phase 3 completed in $((SECONDS - phase_start))s"

  confirm_gate 3 "Data loaded into target Valkey"
fi

# ── Phase 4: Archive original v1 records ────────────────────────────────────────
#
# Restores original v1 dump binaries as _original_* keys in the TARGET with
# 30-day TTL. This provides an audit trail and rollback reference.
#
# This runs AFTER load (Phase 3) so the v2 records are already in place.
# The script reads JSONL files from disk and writes to the TARGET Redis.

if [ "$START_PHASE" -le 4 ]; then
  CURRENT_PHASE=4
  log_phase 4 "Archive original v1 records in target (30-day TTL)"

  phase_start=$SECONDS

  ruby scripts/upgrades/v0.24.0/enrich_with_original_record.rb \
    --redis-url="$TARGET_VALKEY_URL" \
    --input-dir="$DATA_DIR" \
    $DRY_RUN_FLAG

  echo ""
  echo "  Phase 4 completed in $((SECONDS - phase_start))s"

  confirm_gate 4 "Original v1 records archived with 30-day TTL"
fi

# ── Phase 5: Sync to Auth SQL ──────────────────────────────────────────────────
#
# bin/ots customers sync-auth-accounts boots the full OTS application.
# It reads Customer records from Redis (expects Familia v2 layout in DB 0)
# and creates/updates corresponding accounts in the Rodauth SQL database.
#
# PREREQUISITE: OTS application config must point to the TARGET Redis.
# This command does not accept --redis-url; it uses the app's own config.
#
# Without --run, the command performs a dry-run preview by default.

if [ "$START_PHASE" -le 5 ]; then
  CURRENT_PHASE=5
  log_phase 5 "Sync customer accounts to Auth SQL database"

  phase_start=$SECONDS

  echo "  NOTE: bin/ots reads Redis and database config from the application"
  echo "  configuration file. Verify it points to the TARGET before proceeding."
  echo ""

  if $EXECUTE; then
    # sync-auth-accounts without --run does a preview;
    # with --run it performs the actual sync. Both are useful.
    echo "  Running preview first..."
    bin/ots customers sync-auth-accounts || true
    echo ""

    if ! $SKIP_GATES; then
      read -rp "  Preview above. Execute the sync? [y/N] " response
      case "$response" in
        [yY]|[yY][eE][sS]) ;;
        *)
          echo "  Sync skipped. Run manually: bin/ots customers sync-auth-accounts --run"
          echo ""
          echo "  Phase 5 skipped (operator choice)"
          # Don't exit -- proceed to summary
          CURRENT_PHASE=5
          phase_start=$SECONDS
          # Jump to summary
          echo "  Phase 5 completed in $((SECONDS - phase_start))s (skipped)"
          # Use a variable to track skip
          PHASE5_SKIPPED=true
          ;;
      esac
    fi

    if [ "${PHASE5_SKIPPED:-false}" = "false" ]; then
      bin/ots customers sync-auth-accounts --run
    fi
  else
    echo "  DRY-RUN: Would execute:"
    echo "    bin/ots customers sync-auth-accounts        (preview)"
    echo "    bin/ots customers sync-auth-accounts --run   (execute)"
    echo ""
    echo "  The sync-auth-accounts command is idempotent (upserts by external_id)."
    echo "  It can be re-run safely if interrupted."
  fi

  echo ""
  echo "  Phase 5 completed in $((SECONDS - phase_start))s"
fi

# ── Summary ─────────────────────────────────────────────────────────────────────

echo ""
echo "+-----------------------------------------------------------------------+"
echo "|  UPGRADE COMPLETE                                                      |"
echo "+-----------------------------------------------------------------------+"
echo "|"
echo "|  Mode:           $MODE"
echo "|  Total time:     $((SECONDS - PIPELINE_START))s"
echo "|  Log file:       $LOG_FILE"
echo "|  Data directory:  $DATA_DIR"
echo "|"

if $EXECUTE; then
  echo "|  Post-upgrade checklist:"
  echo "|"
  echo "|    [ ] Verify target keyspace counts match transform summaries"
  echo "|        valkey-cli -u \$TARGET_VALKEY_URL INFO keyspace"
  echo "|"
  echo "|    [ ] Spot-check customer records"
  echo "|        bin/ots customers --list"
  echo "|"
  echo "|    [ ] Spot-check domain records"
  echo "|        bin/ots domains --list"
  echo "|"
  echo "|    [ ] Verify auth sync completed"
  echo "|        Check Auth database account count matches customer count"
  echo "|"
  echo "|    [ ] Verify _original_* audit keys exist with ~30-day TTL"
  echo "|        valkey-cli -u \$TARGET_VALKEY_URL --scan --pattern '*_original_*' | head -5"
  echo "|"
  echo "|    [ ] Start application and verify login flow"
  echo "|"
  echo "|    [ ] Original v1 records will auto-expire in 30 days"
  echo "|"
else
  echo "|  This was a DRY-RUN. No data was modified."
  echo "|  Re-run with --execute to perform the migration."
  echo "|"
fi

echo "+-----------------------------------------------------------------------+"
