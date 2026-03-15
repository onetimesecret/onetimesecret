#!/usr/bin/env bash
#
# v2-capture.sh — Capture V2 API request/response pairs from a running OTS instance.
#
# Usage:
#   ./v2-capture.sh <base_url> <output_dir> [username] [apitoken]
#
# Examples:
#   ./v2-capture.sh http://localhost:3000 ./captures/v0.24.0-v2 user@example.com abc123
#   ./v2-capture.sh https://staging.onetimesecret.com ./captures/v0.25.0-v2 user@example.com xyz789
#
# Produces one JSON file per test case in output_dir, each containing:
#   { request: {...}, response: { status, headers, body }, timing_ms }
#
# Requirements: curl, jq
#
# V2 API differences from V1:
#   - All endpoints under /api/v2/ prefix
#   - JSON-only (no form-encoded)
#   - Vocabulary: identifier (not metadata_key/secret_key), receipt (not metadata),
#     previewed/revealed (not viewed/received)
#   - Nested request bodies: {"secret":{"secret":"...","ttl":300}}
#   - Response shape: { "record": { "receipt": { "identifier": "..." }, "secret": { "identifier": "..." } } }

set -euo pipefail

BASE_URL="${1:?Usage: $0 <base_url> <output_dir> [username] [apitoken]}"
OUTPUT_DIR="${2:?Usage: $0 <base_url> <output_dir> [username] [apitoken]}"
USERNAME="${3:-}"
APITOKEN="${4:-}"

mkdir -p "$OUTPUT_DIR"

# Timestamp for this run
RUN_ID=$(date +%Y%m%d-%H%M%S)
RUN_DIR="$OUTPUT_DIR/$RUN_ID"
mkdir -p "$RUN_DIR"

# Auth header construction
AUTH_ARGS=()
if [[ -n "$USERNAME" && -n "$APITOKEN" ]]; then
  AUTH_ARGS=(-u "${USERNAME}:${APITOKEN}")
fi

# ─── Helpers ───────────────────────────────────────────────────────────

capture() {
  local test_name="$1"
  local method="$2"
  local path="$3"
  shift 3
  local extra_args=("$@")

  local url="${BASE_URL}/api/v2${path}"
  local outfile="${RUN_DIR}/${test_name}.json"
  local tmpfile
  tmpfile=$(mktemp)

  # Capture full response: status, headers, body
  local http_code
  http_code=$(curl -s -w '%{http_code}' \
    -X "$method" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    "${AUTH_ARGS[@]}" \
    -D "${tmpfile}.headers" \
    -o "${tmpfile}.body" \
    "${extra_args[@]}" \
    "$url" 2>/dev/null) || http_code="000"

  # Parse response body as JSON (or capture raw if not JSON)
  local body_json
  if jq . "${tmpfile}.body" >/dev/null 2>&1; then
    body_json=$(jq . "${tmpfile}.body")
  else
    body_json=$(jq -Rs . "${tmpfile}.body")
  fi

  # Parse response headers into JSON object
  local headers_json
  headers_json=$(awk '
    BEGIN { printf "{" }
    /^[A-Za-z]/ {
      gsub(/\r/, "")
      split($0, a, ": ")
      key = tolower(a[1])
      val = a[2]
      for (i=3; i<=length(a); i++) val = val ": " a[i]
      if (started) printf ","
      printf "\"%s\":\"%s\"", key, val
      started = 1
    }
    END { printf "}" }
  ' "${tmpfile}.headers" 2>/dev/null | jq . 2>/dev/null || echo '{}')

  # Build request record
  local request_json
  request_json=$(jq -n \
    --arg method "$method" \
    --arg path "$path" \
    --arg url "$url" \
    --argjson extras "$(printf '%s\n' "${extra_args[@]}" | jq -Rs 'split("\n") | map(select(length > 0))')" \
    '{method: $method, path: $path, url: $url, curl_extras: $extras}')

  # Assemble full capture
  jq -n \
    --arg test "$test_name" \
    --arg run "$RUN_ID" \
    --argjson request "$request_json" \
    --arg status "$http_code" \
    --argjson headers "$headers_json" \
    --argjson body "$body_json" \
    '{
      test_name: $test,
      run_id: $run,
      request: $request,
      response: {
        status: ($status | tonumber),
        headers: $headers,
        body: $body
      }
    }' > "$outfile"

  # Cleanup
  rm -f "$tmpfile" "${tmpfile}.headers" "${tmpfile}.body"

  echo "  [$http_code] $test_name"
}

# ─── Test Cases ────────────────────────────────────────────────────────

echo "=== OTS V2 API Capture ==="
echo "Target: $BASE_URL"
echo "Output: $RUN_DIR"
echo "Auth:   ${USERNAME:-anonymous}"
echo ""

# ── 1. Status & Health ──

echo "--- Status & Health ---"
capture "01-status-get" GET "/status"
capture "02-version-get" GET "/version"
capture "03-supported-locales" GET "/supported-locales"

# ── 2. Secret Creation ──

echo "--- Secret Creation ---"

# Conceal with minimal params
capture "10-conceal-minimal" POST "/secret/conceal" \
  -d '{"secret":{"secret":"test secret value for capture","ttl":300}}'

# Conceal with all params
capture "11-conceal-full" POST "/secret/conceal" \
  -d '{"secret":{"secret":"full param test","ttl":600,"passphrase":"testpass123","recipient":""}}'

# Generate with defaults
capture "12-generate-default" POST "/secret/generate" \
  -d '{"secret":{}}'

# Generate with TTL
capture "13-generate-with-ttl" POST "/secret/generate" \
  -d '{"secret":{"ttl":3600}}'

# Conceal without nesting (should fail or be handled differently)
capture "14-conceal-flat-body" POST "/secret/conceal" \
  -d '{"secret":"flat body test","ttl":300}'

# ── 3. Edge Cases: Creation ──

echo "--- Creation Edge Cases ---"

# Empty secret
capture "20-conceal-empty-secret" POST "/secret/conceal" \
  -d '{"secret":{"secret":"","ttl":300}}'

# Very short TTL (below minimum)
capture "21-conceal-ttl-too-low" POST "/secret/conceal" \
  -d '{"secret":{"secret":"low ttl test","ttl":1}}'

# Very long TTL (above maximum)
capture "22-conceal-ttl-too-high" POST "/secret/conceal" \
  -d '{"secret":{"secret":"high ttl test","ttl":99999999}}'

# Missing secret field entirely
capture "23-conceal-no-secret-field" POST "/secret/conceal" \
  -d '{"secret":{"ttl":300}}'

# Unicode content
capture "24-conceal-unicode" POST "/secret/conceal" \
  -d '{"secret":{"secret":"emoji 🔑 and CJK 秘密 and diacritics über","ttl":300}}'

# Large-ish secret (2KB)
LARGE_SECRET=$(python3 -c "print('A' * 2048)")
capture "25-conceal-large" POST "/secret/conceal" \
  -d "{\"secret\":{\"secret\":\"${LARGE_SECRET}\",\"ttl\":300}}"

# Passphrase edge cases
capture "26-conceal-short-passphrase" POST "/secret/conceal" \
  -d '{"secret":{"secret":"short pass test","ttl":300,"passphrase":"ab"}}'

capture "27-conceal-long-passphrase" POST "/secret/conceal" \
  -d '{"secret":{"secret":"long pass test","ttl":300,"passphrase":"abcdefghijklmnopqrstuvwxyz1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ!@#$%^&*()_+"}}'

# ── 4. Secret Retrieval & Reveal ──

echo "--- Secret Retrieval & Reveal ---"

# Create a secret, then retrieve/reveal it
CREATE_RESP=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  "${AUTH_ARGS[@]}" \
  -d '{"secret":{"secret":"retrieval test secret","ttl":300}}' \
  "${BASE_URL}/api/v2/secret/conceal" 2>/dev/null)

SECRET_ID=$(echo "$CREATE_RESP" | jq -r '.record.secret.identifier // empty' 2>/dev/null)
RECEIPT_ID=$(echo "$CREATE_RESP" | jq -r '.record.receipt.identifier // empty' 2>/dev/null)

if [[ -n "$SECRET_ID" ]]; then
  # Show secret (GET — preview/status info, does not reveal)
  capture "30-show-secret" GET "/secret/${SECRET_ID}"

  # Show secret status
  capture "31-show-secret-status" GET "/secret/${SECRET_ID}/status"

  # Reveal secret
  capture "32-reveal-secret" POST "/secret/${SECRET_ID}/reveal" \
    -d '{"continue":true}'
else
  echo "  [SKIP] Could not create secret for retrieval tests"
fi

# Reveal non-existent secret
capture "33-reveal-nonexistent" POST "/secret/nonexistent_key_12345/reveal" \
  -d '{"continue":true}'

# ── 5. Receipt Retrieval ──

echo "--- Receipt Retrieval ---"

# Create another secret for receipt tests
CREATE_RESP2=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  "${AUTH_ARGS[@]}" \
  -d '{"secret":{"secret":"receipt test secret","ttl":300}}' \
  "${BASE_URL}/api/v2/secret/conceal" 2>/dev/null)

RECEIPT_ID2=$(echo "$CREATE_RESP2" | jq -r '.record.receipt.identifier // empty' 2>/dev/null)

if [[ -n "$RECEIPT_ID2" ]]; then
  # GET /receipt/:identifier
  capture "40-receipt-get" GET "/receipt/${RECEIPT_ID2}"

  # GET /private/:identifier (alias)
  capture "41-private-get" GET "/private/${RECEIPT_ID2}"

  # Create separate secrets for POST-based receipt access
  CREATE_RESP2B=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    "${AUTH_ARGS[@]}" \
    -d '{"secret":{"secret":"receipt alias test","ttl":300}}' \
    "${BASE_URL}/api/v2/secret/conceal" 2>/dev/null)

  RECEIPT_ID2B=$(echo "$CREATE_RESP2B" | jq -r '.record.receipt.identifier // empty' 2>/dev/null)

  if [[ -n "$RECEIPT_ID2B" ]]; then
    # GET /receipt/:identifier (second receipt)
    capture "42-receipt-get-2" GET "/receipt/${RECEIPT_ID2B}"

    # GET /private/:identifier (alias, second receipt)
    capture "43-private-get-2" GET "/private/${RECEIPT_ID2B}"
  fi
else
  echo "  [SKIP] Could not create secret for receipt tests"
fi

# Non-existent receipt
capture "46-receipt-nonexistent" GET "/receipt/nonexistent_receipt_key"
capture "47-private-nonexistent" GET "/private/nonexistent_receipt_key"

# ── 6. Recent Receipts ──

echo "--- Recent Receipts ---"
capture "50-receipt-recent" GET "/receipt/recent"
capture "51-private-recent" GET "/private/recent"

# Recent without auth
SAVE_AUTH_RECENT=("${AUTH_ARGS[@]}")
AUTH_ARGS=()
capture "52-receipt-recent-no-auth" GET "/receipt/recent"
AUTH_ARGS=("${SAVE_AUTH_RECENT[@]}")

# ── 6b. Update Receipt ──

echo "--- Update Receipt ---"

# Create a secret for receipt update test
CREATE_RESP_MEMO=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  "${AUTH_ARGS[@]}" \
  -d '{"secret":{"secret":"memo test secret","ttl":300}}' \
  "${BASE_URL}/api/v2/secret/conceal" 2>/dev/null)

RECEIPT_ID_MEMO=$(echo "$CREATE_RESP_MEMO" | jq -r '.record.receipt.identifier // empty' 2>/dev/null)

if [[ -n "$RECEIPT_ID_MEMO" ]]; then
  capture "55-update-receipt-memo" PATCH "/receipt/${RECEIPT_ID_MEMO}" \
    -d '{"memo":"a note about this secret"}'
else
  echo "  [SKIP] Could not create secret for receipt update test"
fi

# ── 7. Burn ──

echo "--- Burn ---"

# Create a secret to burn via /receipt/ path
CREATE_RESP3=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  "${AUTH_ARGS[@]}" \
  -d '{"secret":{"secret":"burn test secret","ttl":300}}' \
  "${BASE_URL}/api/v2/secret/conceal" 2>/dev/null)

RECEIPT_ID3=$(echo "$CREATE_RESP3" | jq -r '.record.receipt.identifier // empty' 2>/dev/null)

if [[ -n "$RECEIPT_ID3" ]]; then
  # Burn via /receipt/:identifier/burn
  capture "60-burn-receipt" POST "/receipt/${RECEIPT_ID3}/burn" \
    -d '{"continue":true}'

  # Try to access receipt after burn
  capture "61-receipt-after-burn" GET "/receipt/${RECEIPT_ID3}"
else
  echo "  [SKIP] Could not create secret for burn tests"
fi

# Create another to burn via /private/ alias
CREATE_RESP4=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  "${AUTH_ARGS[@]}" \
  -d '{"secret":{"secret":"burn test secret 2","ttl":300}}' \
  "${BASE_URL}/api/v2/secret/conceal" 2>/dev/null)

RECEIPT_ID4=$(echo "$CREATE_RESP4" | jq -r '.record.receipt.identifier // empty' 2>/dev/null)

if [[ -n "$RECEIPT_ID4" ]]; then
  capture "62-burn-private-alias" POST "/private/${RECEIPT_ID4}/burn" \
    -d '{"continue":true}'
else
  echo "  [SKIP] Could not create secret for private burn test"
fi

# Burn non-existent
capture "63-burn-nonexistent" POST "/receipt/nonexistent_burn_key/burn" \
  -d '{"continue":true}'

# ── 8. Passphrase-Protected Secrets ──

echo "--- Passphrase Protected ---"

CREATE_RESP5=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  "${AUTH_ARGS[@]}" \
  -d '{"secret":{"secret":"passphrase protected secret","ttl":300,"passphrase":"correct-horse-battery"}}' \
  "${BASE_URL}/api/v2/secret/conceal" 2>/dev/null)

SECRET_ID5=$(echo "$CREATE_RESP5" | jq -r '.record.secret.identifier // empty' 2>/dev/null)
RECEIPT_ID5=$(echo "$CREATE_RESP5" | jq -r '.record.receipt.identifier // empty' 2>/dev/null)

if [[ -n "$SECRET_ID5" ]]; then
  # Try to reveal without passphrase
  capture "70-reveal-no-passphrase" POST "/secret/${SECRET_ID5}/reveal" \
    -d '{"continue":true}'

  # Try with wrong passphrase
  capture "71-reveal-wrong-passphrase" POST "/secret/${SECRET_ID5}/reveal" \
    -d '{"passphrase":"wrong-pass","continue":true}'

  # Correct passphrase
  capture "72-reveal-correct-passphrase" POST "/secret/${SECRET_ID5}/reveal" \
    -d '{"passphrase":"correct-horse-battery","continue":true}'

  # Receipt should show passphrase_required
  if [[ -n "$RECEIPT_ID5" ]]; then
    capture "73-receipt-shows-passphrase" GET "/receipt/${RECEIPT_ID5}"
  fi
else
  echo "  [SKIP] Could not create passphrase-protected secret"
fi

# ── 9. Auth Edge Cases ──

echo "--- Auth Edge Cases ---"

# Bad credentials (override auth args for these tests)
SAVE_AUTH=("${AUTH_ARGS[@]}")
AUTH_ARGS=(-u "baduser@example.com:invalidtoken")
capture "80-bad-credentials-status" GET "/status"
capture "81-bad-auth-conceal" POST "/secret/conceal" \
  -d '{"secret":{"secret":"should fail","ttl":300}}'
capture "82-bad-auth-recent" GET "/receipt/recent"
AUTH_ARGS=("${SAVE_AUTH[@]}")

# No auth at all
SAVE_AUTH2=("${AUTH_ARGS[@]}")
AUTH_ARGS=()
capture "83-no-auth-conceal" POST "/secret/conceal" \
  -d '{"secret":{"secret":"anonymous test","ttl":300}}'
capture "84-no-auth-generate" POST "/secret/generate" \
  -d '{"secret":{"ttl":300}}'
AUTH_ARGS=("${SAVE_AUTH2[@]}")

# ── 10. CORS Preflight ──

echo "--- CORS Preflight ---"
capture "85-options-conceal" OPTIONS "/secret/conceal" \
  -H "Origin: https://example.com" \
  -H "Access-Control-Request-Method: POST"

capture "86-options-generate" OPTIONS "/secret/generate" \
  -H "Origin: https://example.com" \
  -H "Access-Control-Request-Method: POST"

# ── 11. Bulk Secret Status ──

echo "--- Bulk Secret Status ---"

# Create two secrets for bulk status check
BULK_RESP1=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  "${AUTH_ARGS[@]}" \
  -d '{"secret":{"secret":"bulk status test 1","ttl":300}}' \
  "${BASE_URL}/api/v2/secret/conceal" 2>/dev/null)

BULK_RESP2=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  "${AUTH_ARGS[@]}" \
  -d '{"secret":{"secret":"bulk status test 2","ttl":300}}' \
  "${BASE_URL}/api/v2/secret/conceal" 2>/dev/null)

BULK_SECRET_ID1=$(echo "$BULK_RESP1" | jq -r '.record.secret.identifier // empty' 2>/dev/null)
BULK_SECRET_ID2=$(echo "$BULK_RESP2" | jq -r '.record.secret.identifier // empty' 2>/dev/null)

if [[ -n "$BULK_SECRET_ID1" && -n "$BULK_SECRET_ID2" ]]; then
  capture "87-bulk-secret-status" POST "/secret/status" \
    -d "{\"identifiers\":[\"${BULK_SECRET_ID1}\",\"${BULK_SECRET_ID2}\"]}"
else
  echo "  [SKIP] Could not create secrets for bulk status test"
fi

# ── Summary ──

echo ""
echo "=== Capture Complete ==="
TOTAL=$(find "$RUN_DIR" -name "*.json" | wc -l)
echo "Captured $TOTAL test cases in $RUN_DIR"
echo ""
echo "Next: run against both versions, then diff with:"
echo "  ./v2-diff.sh $RUN_DIR <other_run_dir>"
