#!/usr/bin/env bash
# PoC 03 — Passphrase brute-force protection, incl. X-Forwarded-For bypass attempt
#          (EXPECTED RESULT: CLEAN — locks at 5, XFF rotation does not help)
set -euo pipefail
BASE="${BASE:-http://127.0.0.1:3000}"

mk_secret() {
  curl -sS -m 10 -X POST "$BASE/api/v2/secret/conceal" -H 'Content-Type: application/json' \
    -d '{"secret":{"secret":"PASSPHRASE-PROBE","ttl":3600,"passphrase":"correcthorse"}}' \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["record"]["receipt"]["secret_identifier"])'
}

probe() { # $1=secret  $2=extra curl args...
  local sk="$1"; shift
  for i in $(seq 1 25); do
    printf '%s ' "$(curl -sS -m 10 -o /dev/null -w '%{http_code}' \
      -X POST "$BASE/api/v2/secret/$sk/reveal" -H 'Content-Type: application/json' \
      "$@" -d "{\"continue\":true,\"passphrase\":\"wrong$i\"}")"
  done; echo
}

echo "=== baseline (same source IP) ==="
probe "$(mk_secret)"
echo "expected: 422 x5 then 429 (locked, retry_after 1800)"

echo
echo "=== X-Forwarded-For rotated on every attempt ==="
SK=$(mk_secret)
for i in $(seq 1 25); do
  printf '%s ' "$(curl -sS -m 10 -o /dev/null -w '%{http_code}' \
    -X POST "$BASE/api/v2/secret/$SK/reveal" -H 'Content-Type: application/json' \
    -H "X-Forwarded-For: 203.0.113.$i" -d "{\"continue\":true,\"passphrase\":\"wrong$i\"}")"
done; echo
echo "expected: IDENTICAL to baseline — XFF is not trusted without a configured trusted proxy"
