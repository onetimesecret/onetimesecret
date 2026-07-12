#!/usr/bin/env bash
#
# scripts/test-install/proof-of-life.sh <base-url>
#
# The standard behavior-based smoke assertion, shared by every install lane
# (install-onboarding testing-strategy §4). Behavior, not logs: log-text
# asserts are brittle and none of the verified reference projects use them.
#
#   1. GET /api/v2/status           -> 200
#   2. GET /                        -> 200, AND a referenced /dist/assets/*.js
#                                      -> 200  (the status endpoint reported
#                                      "nominal" while the UI was assetless;
#                                      the asset round-trip is what catches a
#                                      build-less boot)
#   3. API round-trip (the product's core invariant as a smoke test):
#      create a secret -> retrieve it once (value matches) -> second retrieval
#      is gone (at-most-once).
#   4. (opt-in: POL_CREATE_ACCOUNT=1) first account: `bin/ots apitoken
#      --create --role colonel` -> authenticated GET /api/v2/receipt/recent
#      is 200 (basicauth-only route, so a 200 proves the credentials).
#      Default off — see the step-4 section below for POL_* env vars.
#
# Packaged once so Tier 1 (run.sh), 2a (compose-smoke), 2b (installer-matrix)
# and any future Goss spec call the identical assertion.
#
# Usage:
#   scripts/test-install/proof-of-life.sh http://127.0.0.1:3000
#
# Exit 0 = the instance is alive and the core loop works; nonzero = a specific
# assertion failed (message on stderr names which).

set -euo pipefail

BASE="${1:-}"
if [[ -z "$BASE" ]]; then
  echo "usage: $0 <base-url>   e.g. http://127.0.0.1:3000" >&2
  exit 64
fi
BASE="${BASE%/}"

pass() { printf '  OK: %s\n' "$1"; }
die()  { printf 'PROOF-OF-LIFE FAILED: %s\n' "$1" >&2; exit 1; }

# curl base flags. --retry-connrefused + retries ride out a just-booted server.
# No --fail here: callers that expect a non-2xx (the burned-secret 404) inspect
# the status code themselves.
curl_code() {  # <url> [extra curl args...] -> prints HTTP status code
  local url="$1"; shift
  curl --silent --show-error --output /dev/null \
       --retry 10 --retry-connrefused --retry-delay 1 --max-time 20 \
       --write-out '%{http_code}' "$@" "$url"
}
curl_body() {  # <url> [extra curl args...] -> prints "BODY\n<status>"
  local url="$1"; shift
  curl --silent --show-error \
       --retry 10 --retry-connrefused --retry-delay 1 --max-time 20 \
       --write-out '\n%{http_code}' "$@" "$url"
}

# --- 1. status endpoint -------------------------------------------------------
echo "1. GET /api/v2/status"
code="$(curl_code "$BASE/api/v2/status")"
[[ "$code" == "200" ]] || die "GET /api/v2/status returned $code (want 200)"
pass "status endpoint 200"

# --- 2. homepage + a referenced asset -----------------------------------------
echo "2. GET / and a referenced /dist/assets/*.js"
home="$(curl --silent --show-error --retry 10 --retry-connrefused \
             --retry-delay 1 --max-time 20 --write-out '\n%{http_code}' "$BASE/")"
home_code="${home##*$'\n'}"
home_html="${home%$'\n'*}"
[[ "$home_code" == "200" ]] || die "GET / returned $home_code (want 200)"
pass "homepage 200"

asset="$(printf '%s' "$home_html" | grep -oE '/dist/assets/[A-Za-z0-9._-]+\.js' | head -n1 || true)"
if [[ -z "$asset" ]]; then
  die "GET / served no /dist/assets/*.js reference — the UI is assetless (run 'pnpm run build')"
fi
asset_code="$(curl_code "$BASE$asset")"
[[ "$asset_code" == "200" ]] || die "referenced asset $asset returned $asset_code (want 200)"
pass "asset $asset serves 200"

# --- 3. API round-trip: create -> reveal (once) -> gone ------------------------
echo "3. API round-trip (create -> reveal -> at-most-once)"
nonce="proof-of-life $(date -u +%Y-%m-%dT%H:%M:%SZ) $$-${RANDOM}"

create="$(curl_body "$BASE/api/v1/share" -X POST -d "secret=$nonce" -d 'ttl=300')"
create_code="${create##*$'\n'}"
create_body="${create%$'\n'*}"
[[ "$create_code" == "200" ]] || die "POST /api/v1/share returned $create_code (want 200): $create_body"

secret_key="$(printf '%s' "$create_body" | grep -oE '"secret_key"[[:space:]]*:[[:space:]]*"[^"]+"' | head -n1 | sed -E 's/.*"secret_key"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
[[ -n "$secret_key" ]] || die "share response had no secret_key: $create_body"
pass "secret created (key ${secret_key:0:8}…)"

reveal="$(curl_body "$BASE/api/v1/secret/$secret_key" -X POST)"
reveal_code="${reveal##*$'\n'}"
reveal_body="${reveal%$'\n'*}"
[[ "$reveal_code" == "200" ]] || die "first reveal returned $reveal_code (want 200): $reveal_body"
value="$(printf '%s' "$reveal_body" | grep -oE '"value"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*"value"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
[[ "$value" == "$nonce" ]] || die "revealed value did not match what was stored (got: ${value:-<empty>})"
pass "secret revealed once, value matches"

gone_code="$(curl_code "$BASE/api/v1/secret/$secret_key" -X POST)"
[[ "$gone_code" == "404" ]] || die "second reveal returned $gone_code (want 404 — at-most-once violated)"
pass "second reveal is gone (at-most-once holds)"

# --- 4. (opt-in) first account: create -> authenticated API 200 ----------------
#
# Strictly opt-in via POL_CREATE_ACCOUNT=1; default off means existing callers
# see byte-for-byte identical behavior. Env vars:
#
#   POL_CREATE_ACCOUNT  "1" enables this step (default: skipped entirely).
#   POL_EXEC            optional command prefix that reaches a shell where
#                       bin/ots works, e.g.
#                         "docker compose -f docker/compose/docker-compose.simple.yml exec -T app"
#                         "docker exec $CTR"
#                       Empty (default) runs bin/ots in the current directory
#                       (bare-metal: Valkey up and .env sourced).
#   POL_ACCOUNT_EMAIL   optional; must be fresh per run (`apitoken --create`
#                       exits 1 if the customer exists). Default is randomized.
if [[ "${POL_CREATE_ACCOUNT:-0}" == "1" ]]; then
  echo "4. first account (opt-in): create -> authenticated API 200"
  pol_email="${POL_ACCOUNT_EMAIL:-pol-$$-${RANDOM}@example.com}"
  # Unquoted POL_EXEC expansion is deliberate: it is a command prefix.
  # shellcheck disable=SC2086
  apitoken_out="$(${POL_EXEC:-} bin/ots apitoken "$pol_email" --create --role colonel)" \
    || die "bin/ots apitoken --create failed for $pol_email"
  pol_token="$(printf '%s' "$apitoken_out" | grep -E '^API Token: ' | head -n1 | sed 's/^API Token: //')"
  [[ -n "$pol_token" ]] || die "apitoken output had no 'API Token: ' line: $apitoken_out"
  pass "account $pol_email created with API token"

  # /api/v2/receipt/recent is auth=basicauth with no noauth fallback: a 200
  # can only mean the email:token pair authenticated. Prove that premise
  # first — anonymous must NOT get a 200 — so the authenticated 200 means
  # something.
  noauth_code="$(curl_code "$BASE/api/v2/receipt/recent")"
  [[ "$noauth_code" != "200" ]] \
    || die "unauthenticated GET /api/v2/receipt/recent returned 200 — endpoint cannot prove credentials"
  pass "endpoint rejects anonymous ($noauth_code)"

  auth_code="$(curl_code "$BASE/api/v2/receipt/recent" -u "$pol_email:$pol_token")"
  [[ "$auth_code" == "200" ]] || die "authenticated GET /api/v2/receipt/recent returned $auth_code (want 200)"
  pass "authenticated API round-trip 200"
fi

echo "Proof of life: instance is alive and the core secret loop works."
