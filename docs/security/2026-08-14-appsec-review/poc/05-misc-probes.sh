#!/usr/bin/env bash
# PoC 05 — Assorted single-shot probes used during the review.
set -euo pipefail
BASE="${BASE:-http://127.0.0.1:3000}"

check_curl() {
  local code body
  body=$(curl -sS -m 10 -w '\n%{http_code}' "$@" 2>&1) || { echo "ERROR: curl failed"; return 1; }
  code=$(echo "$body" | tail -1)
  [[ "$code" == 2* || "$code" == 3* ]] || { echo "ERROR: HTTP $code"; return 1; }
  echo "$body" | sed '$d'
}

echo "=== CSP + security headers (expect strict nonce-based CSP) ==="
curl -sSf -D- -o /dev/null -m 8 "$BASE/" \
  | grep -iE 'content-security-policy|x-frame-options|strict-transport|referrer-policy|x-content-type'

echo
echo "=== CORS (expect: no Access-Control-* headers at all) ==="
HDRS=$(curl -sSf -D- -o /dev/null -m 8 -H 'Origin: https://evil.example' "$BASE/api/v2/status") || { echo "ERROR: request failed"; exit 1; }
echo "$HDRS" | grep -i 'access-control' || echo "none — clean"

echo
echo "=== Host header injection (expect links on the CONFIGURED host, not evil.example.com) ==="
check_curl -X POST "$BASE/api/v1/share" -H 'Host: evil.example.com' \
  -d 'secret=HOSTPROBE&ttl=3600' | python3 -c 'import sys,json;print(json.load(sys.stdin)["metadata_url"])'

echo
echo "=== TTL clamping (expect 604800 max, 60 min) ==="
for T in 99999999999 -1; do
  echo -n "requested ttl=$T -> stored "
  check_curl -X POST "$BASE/api/v2/secret/conceal" -H 'Content-Type: application/json' \
    -d "{\"secret\":{\"secret\":\"ttlprobe\",\"ttl\":$T}}" \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["record"]["receipt"]["secret_ttl"])'
done

echo
echo "=== L-3: JSON object accepted for the 'secret' field (schema not type-enforced) ==="
SK=$(check_curl -X POST "$BASE/api/v2/secret/conceal" -H 'Content-Type: application/json' \
  -d '{"secret":{"secret":{"a":"b","c":[1,2]},"ttl":3600}}' \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["record"]["receipt"]["secret_identifier"])')
check_curl -X POST "$BASE/api/v2/secret/$SK/reveal" -H 'Content-Type: application/json' \
  -d '{"continue":true}' \
  | python3 -c 'import sys,json;print("revealed:",repr(json.load(sys.stdin)["record"].get("secret_value")))'

echo
echo "=== Unauthenticated conceal is unthrottled (M-7): 40 rapid creates ==="
OK=0 FAIL=0
for i in $(seq 1 40); do
  CODE=$(curl -sS -m 10 -o /dev/null -w '%{http_code}' -X POST "$BASE/api/v2/secret/conceal" \
    -H 'Content-Type: application/json' -d "{\"secret\":{\"secret\":\"flood$i\",\"ttl\":3600}}")
  printf '%s ' "$CODE"
  [[ "$CODE" == 2* ]] && ((OK++)) || ((FAIL++))
done; echo
echo "expected (current behaviour): 200 x40 — no 429"
[[ $FAIL -gt 0 ]] && echo "WARNING: $FAIL requests failed — verify server is running"
