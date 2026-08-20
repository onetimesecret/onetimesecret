#!/usr/bin/env bash
# PoC 01 — Burn-after-reading under concurrency (EXPECTED RESULT: CLEAN)
#
# Creates one secret, then fires N simultaneous reveals. The product promise is
# that AT MOST ONE caller ever receives the plaintext.
#
# Usage: ./01-burn-after-read-race.sh [concurrency]   (default 10)
set -euo pipefail
BASE="${BASE:-http://127.0.0.1:3000}"
N="${1:-10}"
CANARY="BURN-RACE-CANARY-$$"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

SK=$(curl -sS -m 10 -X POST "$BASE/api/v1/share" \
      -d "secret=$CANARY&ttl=3600" \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["secret_key"])')
echo "secret_key = $SK"
echo "firing $N concurrent reveals..."

for i in $(seq 1 "$N"); do
  curl -sS -m 10 -X POST "$BASE/api/v1/secret/$SK" -d 'continue=true' -o "$TMP/r$i.json" &
done
wait

HITS=$(grep -l "$CANARY" "$TMP"/r*.json 2>/dev/null | wc -l)
echo "responses containing plaintext: $HITS  (expected: 1)"
[ "$HITS" -eq 1 ] && echo "PASS — burn-after-reading holds" || { echo "FAIL — multi-reveal!"; exit 1; }
