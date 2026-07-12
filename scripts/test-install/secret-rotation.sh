#!/usr/bin/env bash
#
# scripts/test-install/secret-rotation.sh
#
# SECRET-rotation harness lane (install-onboarding C10 §5). Proves the
# work-chunk's stated behavior verbatim: the app boots with a rotated SECRET
# and a secret SURVIVES a failed reveal.
#
#   1. Boot clean (SECRET A), create a secret via the v2 API, capture the id.
#   2. Restart with a regenerated SECRET B. Assert the boot log carries the
#      mismatch warning and /health/advanced reports the degraded
#      secret_verifier sub-check.
#   3. Attempt the reveal. Assert a 503 with code secret_undecryptable AND
#      that the secret record still exists with its ciphertext.
#   4. Restore SECRET A, restart. Assert the verifier is ok and the reveal
#      now returns the original plaintext exactly once (second attempt 404s).
#
# Environment: bare-metal, like the fresh-clone lane — needs bundle-installed
# gems, generated/locales + generated/schemas + etc/config.yaml (bin/setup
# provides all three), a redis-server/valkey-server binary, ruby, and curl.
# Starts an ISOLATED throwaway datastore and app instance; never touches the
# dev (6379/5212) or test (2121) datastores.
#
# Usage:
#   scripts/test-install/secret-rotation.sh
#
# Env knobs: ROT_APP_PORT (default 3213), ROT_DB_PORT (default 2129).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

APP_PORT="${ROT_APP_PORT:-3213}"
DB_PORT="${ROT_DB_PORT:-2129}"
BASE="http://127.0.0.1:$APP_PORT"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ots-secret-rotation.XXXXXX")"

pass() { printf '  OK: %s\n' "$1"; }
die()  { printf 'SECRET-ROTATION LANE FAILED: %s\n' "$1" >&2; exit 1; }

# --- prerequisites (fail fast and loud) ---------------------------------------
command -v curl >/dev/null || die "curl not found"
DB_BIN="$(command -v valkey-server || command -v redis-server || true)"
[[ -n "$DB_BIN" ]] || die "no valkey-server/redis-server binary found"
DB_CLI="$(command -v valkey-cli || command -v redis-cli || true)"
[[ -n "$DB_CLI" ]] || die "no valkey-cli/redis-cli binary found"
bundle check &>/dev/null || die "gems not installed (run bin/setup first)"
ls generated/locales/*.json &>/dev/null || die "generated/locales missing (run bin/setup first)"

# --- lifecycle helpers ---------------------------------------------------------
APP_PID=""

start_db() {
  "$DB_BIN" --port "$DB_PORT" --save '' --appendonly no \
            --dir "$WORKDIR" --daemonize yes
  local i
  for i in $(seq 1 20); do
    "$DB_CLI" -p "$DB_PORT" ping &>/dev/null && return 0
    sleep 0.25
  done
  die "throwaway datastore did not answer on :$DB_PORT"
}

# boot_app <secret> <log-file>
# Production-mode boot (the operator path); config comes from the checkout's
# config resolution with every connection/secret knob passed explicitly so
# neither the dev .env nor the dev datastore leaks in.
boot_app() {
  local secret="$1" log="$2"
  RACK_ENV=production \
  SECRET="$secret" \
  VALKEY_URL="redis://127.0.0.1:$DB_PORT/0" \
  REDIS_URL="redis://127.0.0.1:$DB_PORT/0" \
  HOST="127.0.0.1:$APP_PORT" \
  SSL=false \
  AUTHENTICATION_MODE=simple \
  JOBS_ENABLED=false \
    bundle exec puma -b "tcp://127.0.0.1:$APP_PORT" config.ru \
    >"$log" 2>&1 &
  APP_PID=$!

  local i
  for i in $(seq 1 60); do
    if curl --silent --output /dev/null --max-time 2 \
         --write-out '' "$BASE/api/v2/status" 2>/dev/null; then
      code="$(curl --silent --output /dev/null --max-time 5 --write-out '%{http_code}' "$BASE/api/v2/status")"
      [[ "$code" == "200" ]] && return 0
    fi
    kill -0 "$APP_PID" 2>/dev/null || { sed -n '1,40p' "$log" >&2; die "app process exited during boot (log above)"; }
    sleep 1
  done
  sed -n '1,40p' "$log" >&2
  die "app did not answer on :$APP_PORT within 60s (log above)"
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

json_dig() {  # <json-on-stdin> <key...> — prints the dug value or empty
  ruby -rjson -e 'puts JSON.parse($stdin.read).dig(*ARGV).to_s rescue nil' "$@"
}

# --- 1. boot clean with SECRET A, create a secret ------------------------------
echo "1. boot with SECRET A, create a secret"
SECRET_A="$(openssl rand -hex 32)"
SECRET_B="$(openssl rand -hex 32)"
NONCE="rotation-lane $(date -u +%Y-%m-%dT%H:%M:%SZ) $$-${RANDOM}"

start_db
boot_app "$SECRET_A" "$WORKDIR/app-boot1.log"
pass "app answering with SECRET A"

create_body="$(curl --silent --show-error --max-time 20 \
  -X POST "$BASE/api/v2/secret/conceal" \
  -d "secret[secret]=$NONCE" -d 'secret[ttl]=300')"
identifier="$(printf '%s' "$create_body" | json_dig record secret identifier)"
[[ -n "$identifier" ]] || die "conceal response had no record.secret.identifier: $create_body"
pass "secret created (id ${identifier:0:8}…)"

# --- 2. restart with a regenerated SECRET: loud, degraded, non-fatal -----------
echo "2. restart with regenerated SECRET B"
stop_app
boot_app "$SECRET_B" "$WORKDIR/app-boot2.log"
pass "app still boots (secret_verifier_mode: warn must not brick the deploy)"

grep -q 'SECRET MISMATCH' "$WORKDIR/app-boot2.log" \
  || die "boot log carries no SECRET MISMATCH warning (app-boot2.log)"
pass "boot log carries the mismatch warning"

health="$(curl --silent --max-time 10 "$BASE/health/advanced")"
sv_status="$(printf '%s' "$health" | json_dig checks secret_verifier status)"
sv_state="$(printf '%s' "$health" | json_dig checks secret_verifier state)"
top_status="$(printf '%s' "$health" | json_dig status)"
[[ "$sv_status" == "error" && "$sv_state" == "mismatch" ]] \
  || die "/health/advanced secret_verifier is not error/mismatch: $health"
[[ "$top_status" == "degraded" ]] \
  || die "/health/advanced top-level status is not degraded: $health"
pass "/health/advanced reports the degraded secret_verifier sub-check"

# --- 3. the reveal fails SAFE: 503, record and ciphertext survive --------------
echo "3. attempt the reveal under the wrong SECRET"
reveal="$(curl --silent --max-time 20 --write-out '\n%{http_code}' \
  -X POST "$BASE/api/v2/secret/$identifier/reveal" -d 'continue=true')"
reveal_code="${reveal##*$'\n'}"
reveal_body="${reveal%$'\n'*}"
[[ "$reveal_code" == "503" ]] \
  || die "reveal under wrong SECRET returned $reveal_code (want 503): $reveal_body"
printf '%s' "$reveal_body" | grep -q 'secret_undecryptable' \
  || die "503 body carries no secret_undecryptable code: $reveal_body"
pass "reveal refused with 503 secret_undecryptable"

exists="$("$DB_CLI" -p "$DB_PORT" exists "secret:$identifier:object")"
[[ "$exists" == "1" ]] || die "secret record was consumed by the failed reveal (want: survives)"
has_ciphertext="$("$DB_CLI" -p "$DB_PORT" hexists "secret:$identifier:object" ciphertext)"
[[ "$has_ciphertext" == "1" ]] || die "secret record survives but its ciphertext is gone"
pass "secret record and ciphertext survive the failed reveal"

# --- 4. restore SECRET A: verifier ok, reveal works exactly once ---------------
echo "4. restore SECRET A and reveal"
stop_app
boot_app "$SECRET_A" "$WORKDIR/app-boot3.log"

health="$(curl --silent --max-time 10 "$BASE/health/advanced")"
sv_status="$(printf '%s' "$health" | json_dig checks secret_verifier status)"
[[ "$sv_status" == "ok" ]] \
  || die "/health/advanced secret_verifier not ok after restoring SECRET A: $health"
pass "verifier ok after restoring SECRET A"

reveal="$(curl --silent --max-time 20 --write-out '\n%{http_code}' \
  -X POST "$BASE/api/v2/secret/$identifier/reveal" -d 'continue=true')"
reveal_code="${reveal##*$'\n'}"
reveal_body="${reveal%$'\n'*}"
[[ "$reveal_code" == "200" ]] \
  || die "reveal after restore returned $reveal_code (want 200): $reveal_body"
value="$(printf '%s' "$reveal_body" | json_dig record secret_value)"
[[ "$value" == "$NONCE" ]] \
  || die "revealed value does not match the original (got: ${value:-<empty>})"
pass "reveal returns the original plaintext"

gone_code="$(curl --silent --output /dev/null --max-time 20 --write-out '%{http_code}' \
  -X POST "$BASE/api/v2/secret/$identifier/reveal" -d 'continue=true')"
[[ "$gone_code" == "404" ]] \
  || die "second reveal returned $gone_code (want 404 — at-most-once violated)"
pass "second reveal is gone (at-most-once holds)"

echo ""
echo "secret-rotation lane passed: a rotated SECRET is loud, non-destructive, and recoverable."
