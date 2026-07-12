#!/usr/bin/env bash
#
# scripts/test-install/baremetal-boot.sh
#
# Bare-metal boot lane (install-onboarding C7 residuals 1 + 4; clean-room
# validation recipe's middle step, runs 8/8b/9). The only lane that boots
# the app OUTSIDE a container image — everything runs under a POSIX locale
# (LANG=C) so the run-8 locale regression class is guarded at boot, not
# just at secret generation (installer.yml's posix lane covers that leg):
#
#   1. Seed a scratch .env and generate secrets: `rake ots:secrets` under
#      LANG=C (ENV_FILE keeps the checkout's real .env untouched).
#   2. `pnpm run build` under LANG=C — real assets, so proof-of-life's
#      /dist/assets/*.js probe is exercised against a genuine build.
#   3. Boot puma production-mode the documented operator way: the .env
#      sourced with `set -a` (README bare-metal sequence), overriding only
#      the connection/port knobs so the throwaway datastore is used.
#   4. scripts/test-install/proof-of-life.sh — homepage + asset round-trip
#      + v1 create/reveal/at-most-once.
#
# Under LANG=C Ruby's Encoding.default_external is US-ASCII: any reader of
# UTF-8 content (locale JSON, config YAML, .env) that fails to declare its
# encoding crashes here. That crash class shipped once already (run 8).
#
# Environment: bare-metal like the fresh-clone lane — needs bundle-installed
# gems, node_modules, generated/locales + generated/schemas (bin/setup
# provides all of it), a redis-server/valkey-server binary, ruby, and curl.
# Starts an ISOLATED throwaway datastore and app instance; never touches the
# dev (6379/5212) or test (2121) datastores.
#
# Usage:
#   scripts/test-install/baremetal-boot.sh
#
# Env knobs: BM_APP_PORT (default 3214), BM_DB_PORT (default 2130).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# The whole lane — rake, node build, puma, proof-of-life — runs POSIX-locale.
export LANG=C
export LC_ALL=C

APP_PORT="${BM_APP_PORT:-3214}"
DB_PORT="${BM_DB_PORT:-2130}"
BASE="http://127.0.0.1:$APP_PORT"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ots-baremetal-boot.XXXXXX")"
ENV_FILE="$WORKDIR/.env"

pass() { printf '  OK: %s\n' "$1"; }
die()  { printf 'BAREMETAL-BOOT LANE FAILED: %s\n' "$1" >&2; exit 1; }

# --- prerequisites (fail fast and loud) ---------------------------------------
command -v curl >/dev/null || die "curl not found"
command -v pnpm >/dev/null || die "pnpm not found (run bin/setup first)"
DB_BIN="$(command -v valkey-server || command -v redis-server || true)"
[[ -n "$DB_BIN" ]] || die "no valkey-server/redis-server binary found"
DB_CLI="$(command -v valkey-cli || command -v redis-cli || true)"
[[ -n "$DB_CLI" ]] || die "no valkey-cli/redis-cli binary found"
bundle check &>/dev/null || die "gems not installed (run bin/setup first)"
[[ -d node_modules ]] || die "node_modules missing (run bin/setup first)"
ls generated/locales/*.json &>/dev/null || die "generated/locales missing (run bin/setup first)"

# --- lifecycle helpers ---------------------------------------------------------
APP_PID=""

start_db() {
  "$DB_BIN" --port "$DB_PORT" --save '' --appendonly no \
            --dir "$WORKDIR" --daemonize yes
  local _i
  for _i in $(seq 1 20); do
    "$DB_CLI" -p "$DB_PORT" ping &>/dev/null && return 0
    sleep 0.25
  done
  die "throwaway datastore did not answer on :$DB_PORT"
}

stop_app() {
  [[ -n "$APP_PID" ]] || return 0
  kill "$APP_PID" 2>/dev/null || true
  wait "$APP_PID" 2>/dev/null || true
  APP_PID=""
}

cleanup() {
  stop_app
  "$DB_CLI" -p "$DB_PORT" shutdown nosave &>/dev/null || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

# --- 1. seed a scratch .env and generate secrets under LANG=C ------------------
echo "1. rake ots:secrets under LANG=C (scratch env: $ENV_FILE)"
ENV_FILE="$ENV_FILE" bundle exec rake ots:secrets \
  || die "rake ots:secrets failed under LANG=C (run-8 regression class)"
grep -Eq '^SECRET=.+' "$ENV_FILE" \
  || die "rake ots:secrets left SECRET empty in $ENV_FILE"
pass "secrets generated into the scratch .env"

# --- 2. real asset build under LANG=C ------------------------------------------
echo "2. pnpm run build under LANG=C"
pnpm run build >"$WORKDIR/build.log" 2>&1 \
  || { tail -n 40 "$WORKDIR/build.log" >&2; die "pnpm run build failed (log above)"; }
ls public/web/dist/assets/*.js &>/dev/null \
  || die "build produced no public/web/dist/assets/*.js"
pass "assets built"

# --- 3. boot puma production-mode, .env sourced the documented way -------------
echo "3. boot puma (production, LANG=C, .env via set -a)"
start_db
(
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
  export RACK_ENV=production
  export VALKEY_URL="redis://127.0.0.1:$DB_PORT/0"
  export REDIS_URL="redis://127.0.0.1:$DB_PORT/0"
  export HOST="127.0.0.1:$APP_PORT"
  export SSL=false
  export AUTHENTICATION_MODE=simple
  export JOBS_ENABLED=false
  exec bundle exec puma -b "tcp://127.0.0.1:$APP_PORT" config.ru
) >"$WORKDIR/app-boot.log" 2>&1 &
APP_PID=$!

booted=""
for _i in $(seq 1 60); do
  code="$(curl --silent --output /dev/null --max-time 5 --write-out '%{http_code}' \
    "$BASE/api/v2/status" 2>/dev/null || true)"
  if [[ "$code" == "200" ]]; then booted=1; break; fi
  kill -0 "$APP_PID" 2>/dev/null \
    || { sed -n '1,40p' "$WORKDIR/app-boot.log" >&2; die "app process exited during boot (log above)"; }
  sleep 1
done
[[ -n "$booted" ]] \
  || { sed -n '1,40p' "$WORKDIR/app-boot.log" >&2; die "app did not answer on :$APP_PORT within 60s (log above)"; }
pass "puma answering under LANG=C"

# --- 4. proof of life (homepage + asset probe + v1 round-trip) -----------------
echo "4. proof of life"
"$ROOT/scripts/test-install/proof-of-life.sh" "$BASE" \
  || die "proof-of-life failed against the bare-metal boot"

echo ""
echo "baremetal-boot lane passed: secrets, build, boot, and the core loop all work under LANG=C."
