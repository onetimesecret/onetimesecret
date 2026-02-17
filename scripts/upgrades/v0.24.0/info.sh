#!/usr/bin/env bash
# scripts/upgrades/v0.24.0/info.sh
#
# Read-only keyspace inspection for v0.24.0 upgrade source and target databases.
# Equivalent to `valkey-cli info keyspace` plus memory and server version.
#
# This is a companion to upgrade.sh and reset.sh. It never modifies any data.
#
# Usage:
#   scripts/upgrades/v0.24.0/info.sh [OPTIONS]
#
# Options:
#   --source            Show keyspace info for source Redis
#   --target            Show keyspace info for target Valkey
#   --source-url=URL    Source Redis URL (overrides SOURCE_REDIS_URL env)
#   --target-url=URL    Target Valkey URL (overrides TARGET_VALKEY_URL env)
#   --timeout=SECS      Redis operation timeout in seconds (default: 30)
#   --help              Show this help
#
# Environment:
#   SOURCE_REDIS_URL    Redis URL for the v0.23.x source (reads DBs 6,7,8,11)
#   TARGET_VALKEY_URL   Valkey/Redis URL for the v0.24.0 target (DB 0)
#
# If neither --source nor --target is given, both are shown (when URLs are set).
#
# Examples:
#   # Show both (URLs from environment)
#   SOURCE_REDIS_URL=redis://old-host:6379 \
#   TARGET_VALKEY_URL=redis://new-host:6380 \
#     scripts/upgrades/v0.24.0/info.sh
#
#   # Show source only
#   scripts/upgrades/v0.24.0/info.sh --source --source-url=redis://localhost:6379
#
#   # Show target only
#   scripts/upgrades/v0.24.0/info.sh --target --target-url=redis://localhost:6380

set -euo pipefail

# ── Configuration ───────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

SHOW_SOURCE=false
SHOW_TARGET=false
REDIS_TIMEOUT=30

for arg in "$@"; do
  case "$arg" in
    --source)         SHOW_SOURCE=true ;;
    --target)         SHOW_TARGET=true ;;
    --source-url=*)   SOURCE_REDIS_URL="${arg#*=}" ;;
    --target-url=*)   TARGET_VALKEY_URL="${arg#*=}" ;;
    --timeout=*)      REDIS_TIMEOUT="${arg#*=}" ;;
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

# If neither flag is given, show both (when URLs are available)
if ! $SHOW_SOURCE && ! $SHOW_TARGET; then
  SHOW_SOURCE=true
  SHOW_TARGET=true
fi

# ── Verify project root ────────────────────────────────────────────────────────

cd "$PROJECT_ROOT"

if [ ! -f "Gemfile" ] || [ ! -d "scripts/upgrades/v0.24.0" ]; then
  echo "FATAL: Script must run from the onetimesecret project root"
  echo "  Expected: $PROJECT_ROOT"
  exit 1
fi

# ── Helpers ─────────────────────────────────────────────────────────────────────

redact_url() {
  echo "$1" | sed -E 's|(://[^:]*:)[^@]*(@)|\1***\2|'
}

keyspace_info() {
  local label="$1" url="$2"
  echo ""
  echo "=== $label: keyspace info ==="
  echo "  URL: $(redact_url "$url")"
  echo ""

  if ! ruby -e "
    require 'redis'
    require 'uri'
    u = URI.parse(ARGV[0])
    r = Redis.new(url: u.to_s, timeout: ARGV[1].to_i)
    info = r.info('keyspace')
    if info.empty?
      puts '  (no databases with keys)'
    else
      info.sort.each do |db, stats|
        puts \"  #{db}: #{stats}\"
      end
    end
    puts ''
    puts \"  server: #{r.info('server')['redis_version']}\"
    mem = r.info('memory')
    puts \"  used_memory_human: #{mem['used_memory_human']}\"
  " "$url" "$REDIS_TIMEOUT" 2>&1; then
    echo "  FAILED: Cannot connect to $(redact_url "$url")"
    return 1
  fi
}

# ── Show info ─────────────────────────────────────────────────────────────────

SHOWN=0

if $SHOW_SOURCE; then
  if [ -n "${SOURCE_REDIS_URL:-}" ]; then
    keyspace_info "Source Redis" "$SOURCE_REDIS_URL"
    SHOWN=$((SHOWN + 1))
  elif [ "$SHOW_TARGET" = "false" ] || [ -z "${TARGET_VALKEY_URL:-}" ]; then
    # Only complain if source was explicitly requested or nothing else will show
    echo "FATAL: SOURCE_REDIS_URL is required"
    echo "  Set via environment variable or --source-url=URL"
    exit 1
  fi
fi

if $SHOW_TARGET; then
  if [ -n "${TARGET_VALKEY_URL:-}" ]; then
    keyspace_info "Target Valkey" "$TARGET_VALKEY_URL"
    SHOWN=$((SHOWN + 1))
  elif [ "$SHOW_SOURCE" = "false" ] || [ -z "${SOURCE_REDIS_URL:-}" ]; then
    echo "FATAL: TARGET_VALKEY_URL is required"
    echo "  Set via environment variable or --target-url=URL"
    exit 1
  fi
fi

if [ "$SHOWN" -eq 0 ]; then
  echo "No database URLs configured. Set SOURCE_REDIS_URL and/or TARGET_VALKEY_URL."
  exit 1
fi

echo ""
