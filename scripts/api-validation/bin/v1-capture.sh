#!/usr/bin/env bash
#
# v1-capture.sh — Capture V1 API request/response pairs from a running OTS instance.
#
# Usage:
#   ./v1-capture.sh <base_url> <output_dir> [username] [apitoken] [--form]
#
# Options:
#   --form    Send POST data as application/x-www-form-urlencoded instead of
#             application/json. Use this for v0.23.x which lacks Rack::JSONBodyParser.
#
# Examples:
#   ./v1-capture.sh http://localhost:3000 ./captures/v0.23.6 user@example.com abc123 --form
#   ./v1-capture.sh https://staging.onetimesecret.com ./captures/v0.24.0 user@example.com xyz789
#
# Produces one JSON file per test case in output_dir, each containing:
#   { request: {...}, response: { status, headers, body }, timing_ms }
#
# Requirements: curl, jq

set -euo pipefail

BASE_URL="${1:?Usage: $0 <base_url> <output_dir> [username] [apitoken] [--form]}"
OUTPUT_DIR="${2:?Usage: $0 <base_url> <output_dir> [username] [apitoken] [--form]}"
USERNAME="${3:-}"
APITOKEN="${4:-}"

# Detect --form flag in any positional argument
FORM_MODE=false
for arg in "$@"; do
  if [[ "$arg" == "--form" ]]; then
    FORM_MODE=true
    break
  fi
done

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

# json_to_form — Convert a flat JSON object string to form-encoded key=value pairs.
#
# Examples:
#   json_to_form '{"secret":"test value","ttl":300}'  => 'secret=test%20value&ttl=300'
#   json_to_form '{}'                                  => ''
#   json_to_form '{"continue":"true"}'                 => 'continue=true'
#
# Uses Python 3 to parse the JSON and percent-encode values in one step.
# Returns empty string for empty objects.
json_to_form() {
  local json_str="$1"

  # Empty object or empty string — return empty
  if [[ -z "$json_str" ]] || [[ "$json_str" == "{}" ]]; then
    echo ""
    return
  fi

  python3 -c "
import json, sys, urllib.parse
data = json.loads(sys.stdin.read())
if not data:
    sys.exit(0)
# Convert all values to strings, then percent-encode
pairs = []
for k, v in data.items():
    pairs.append(urllib.parse.quote(str(k), safe='') + '=' + urllib.parse.quote(str(v), safe=''))
print('&'.join(pairs))
" <<< "$json_str"
}

# apply_form_mode — Transform extra_args array for form-encoded mode.
#
# When FORM_MODE is active, this rewrites the curl arguments:
#   - Replaces Content-Type: application/json with application/x-www-form-urlencoded
#   - Converts JSON -d payloads to form-encoded format
#   - Drops -d for empty JSON objects (no body needed)
#
# Reads extra_args from the caller's scope and writes FORM_ARGS as output.
apply_form_mode() {
  local -n _in_args=$1
  FORM_ARGS=()

  local i=0
  while (( i < ${#_in_args[@]} )); do
    local arg="${_in_args[$i]}"

    if [[ "$arg" == "-H" ]]; then
      local header="${_in_args[$((i+1))]}"
      if [[ "$header" == "Content-Type: application/json" ]]; then
        # Swap JSON content type for form-encoded
        FORM_ARGS+=(-H "Content-Type: application/x-www-form-urlencoded")
      else
        FORM_ARGS+=(-H "$header")
      fi
      (( i += 2 ))

    elif [[ "$arg" == "-d" ]]; then
      local data="${_in_args[$((i+1))]}"
      if [[ "$data" == "{"* ]]; then
        # JSON payload — convert to form-encoded
        local converted
        converted=$(json_to_form "$data")
        if [[ -n "$converted" ]]; then
          FORM_ARGS+=(-d "$converted")
        fi
        # If converted is empty (from '{}'), skip the -d entirely
      else
        # Already form-encoded or other format — pass through unchanged
        FORM_ARGS+=(-d "$data")
      fi
      (( i += 2 ))

    elif [[ "$arg" == "--data-raw" ]]; then
      # --data-raw with JSON payload — convert to form-encoded -d
      local data="${_in_args[$((i+1))]}"
      if [[ "$data" == "{"* ]]; then
        local converted
        converted=$(json_to_form "$data")
        if [[ -n "$converted" ]]; then
          FORM_ARGS+=(-d "$converted")
        fi
      else
        FORM_ARGS+=(--data-raw "$data")
      fi
      (( i += 2 ))

    else
      FORM_ARGS+=("$arg")
      (( i += 1 ))
    fi
  done
}

capture() {
  local test_name="$1"
  local method="$2"
  local path="$3"
  shift 3
  local extra_args=("$@")

  # In form mode, convert JSON payloads and Content-Type headers
  if [[ "$FORM_MODE" == "true" && "$method" == "POST" && ${#extra_args[@]} -gt 0 ]]; then
    apply_form_mode extra_args
    extra_args=("${FORM_ARGS[@]+"${FORM_ARGS[@]}"}")
  fi

  local url="${BASE_URL}/api/v1${path}"
  local outfile="${RUN_DIR}/${test_name}.json"
  local tmpfile
  tmpfile=$(mktemp)

  # Capture full response: status, headers, body
  # No Content-Type header is set here — each call site provides its own
  # via extra_args when needed. Accept header requests JSON responses.
  local http_code
  http_code=$(curl -s -w '%{http_code}' \
    -X "$method" \
    -H "Accept: application/json" \
    ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} \
    -D "${tmpfile}.headers" \
    -o "${tmpfile}.body" \
    ${extra_args[@]+"${extra_args[@]}"} \
    "$url" 2>/dev/null) || http_code="000"

  # Parse response body as JSON (or capture raw if not JSON)
  local body_json
  if [[ ! -s "${tmpfile}.body" ]]; then
    body_json='null'
  elif jq . "${tmpfile}.body" >/dev/null 2>&1; then
    body_json=$(jq . "${tmpfile}.body")
  else
    body_json=$(jq -Rs . "${tmpfile}.body") || body_json='null'
  fi

  # Parse response headers into JSON object
  local headers_json
  headers_json=$(
    grep -E '^[A-Za-z]' "${tmpfile}.headers" 2>/dev/null | \
    sed 's/\r$//' | \
    jq -Rs '
      split("\n") | map(select(length > 0)) |
      map(capture("^(?<key>[^:]+):\\s*(?<val>.*)")) |
      map({(.key | ascii_downcase): .val}) |
      add // {}
    '
  ) || headers_json='{}'

  # Build request record
  local request_json
  request_json=$(jq -n \
    --arg method "$method" \
    --arg path "$path" \
    --arg url "$url" \
    --argjson extras "$(printf '%s\n' ${extra_args[@]+"${extra_args[@]}"} | jq -Rs 'split("\n") | map(select(length > 0))')" \
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

echo "=== OTS V1 API Capture ==="
echo "Target: $BASE_URL"
echo "Output: $RUN_DIR"
echo "Auth:   ${USERNAME:-anonymous}"
echo "Mode:   $( [[ "$FORM_MODE" == "true" ]] && echo "form-encoded" || echo "json" )"
echo ""

# ── 1. Status & Health ──

echo "--- Status & Health ---"
capture "01-status-get" GET "/status"
capture "02-authcheck-get" GET "/authcheck"
capture "03-authcheck-no-auth" GET "/authcheck"  # Will use auth if provided; separate no-auth test below

# ── 2. Secret Creation ──

echo "--- Secret Creation ---"

# Share with minimal params
capture "10-share-minimal" POST "/share" \
  -H "Content-Type: application/json" \
  -d '{"secret":"test secret value for capture","ttl":300}'

# Share with all params
capture "11-share-full" POST "/share" \
  -H "Content-Type: application/json" \
  -d '{"secret":"full param test","ttl":600,"passphrase":"testpass123","recipient":""}'

# Generate with defaults
capture "12-generate-default" POST "/generate" \
  -H "Content-Type: application/json" \
  -d '{}'

# Generate with params
capture "13-generate-params" POST "/generate" \
  -H "Content-Type: application/json" \
  -d '{"ttl":3600}'

# Create (alias for share) — Always form-encoded so both --form and JSON mode
# send identical requests. Eliminates content-type mismatch in diff results.
capture "14-create-alias" POST "/create" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d 'secret=testing+create+alias&ttl=300'

# ── 3. Edge Cases: Creation ──

echo "--- Creation Edge Cases ---"

# Empty secret
capture "20-share-empty-secret" POST "/share" \
  -H "Content-Type: application/json" \
  -d '{"secret":"","ttl":300}'

# Very short TTL (below minimum)
capture "21-share-ttl-too-low" POST "/share" \
  -H "Content-Type: application/json" \
  -d '{"secret":"low ttl test","ttl":1}'

# Very long TTL (above maximum)
capture "22-share-ttl-too-high" POST "/share" \
  -H "Content-Type: application/json" \
  -d '{"secret":"high ttl test","ttl":99999999}'

# Missing secret field entirely
capture "23-share-no-secret-field" POST "/share" \
  -H "Content-Type: application/json" \
  -d '{"ttl":300}'

# Unicode content
capture "24-share-unicode" POST "/share" \
  -H "Content-Type: application/json" \
  -d '{"secret":"emoji 🔑 and CJK 秘密 and diacritics über","ttl":300}'

# Large-ish secret (2KB)
LARGE_SECRET=$(printf 'A%.0s' {1..2048})
capture "25-share-large" POST "/share" \
  -H "Content-Type: application/json" \
  -d "{\"secret\":\"${LARGE_SECRET}\",\"ttl\":300}"

# Passphrase edge cases
capture "26-share-short-passphrase" POST "/share" \
  -H "Content-Type: application/json" \
  -d '{"secret":"short pass test","ttl":300,"passphrase":"ab"}'

capture "27-share-long-passphrase" POST "/share" \
  -H "Content-Type: application/json" \
  -d '{"secret":"long pass test","ttl":300,"passphrase":"abcdefghijklmnopqrstuvwxyz1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ!@#$%^&*()_+"}'

# ── 4. Secret Retrieval ──

echo "--- Secret Retrieval ---"

# Create a secret, then retrieve it
CREATE_RESP=$(curl -s -X POST \
  -H "Accept: application/json" \
  "${AUTH_ARGS[@]}" \
  -d 'secret=retrieval+test+secret&ttl=300' \
  "${BASE_URL}/api/v1/share" 2>/dev/null)

SECRET_KEY=$(echo "$CREATE_RESP" | jq -r '.secret_key // empty' 2>/dev/null)
METADATA_KEY=$(echo "$CREATE_RESP" | jq -r '.metadata_key // empty' 2>/dev/null)

if [[ -n "$SECRET_KEY" ]]; then
  # Show secret (without continue - should just confirm existence)
  capture "30-show-secret-no-continue" POST "/secret/${SECRET_KEY}"

  # Show secret with continue=true
  capture "31-show-secret-with-continue" POST "/secret/${SECRET_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"continue":"true"}'
else
  echo "  [SKIP] Could not create secret for retrieval tests"
fi

# Retrieve non-existent secret
capture "32-show-secret-nonexistent" POST "/secret/nonexistent_key_12345" \
  -H "Content-Type: application/json" \
  -d '{"continue":"true"}'

# ── 5. Metadata / Private / Receipt ──

echo "--- Metadata/Receipt Retrieval ---"

# Create another secret for metadata tests
CREATE_RESP2=$(curl -s -X POST \
  -H "Accept: application/json" \
  "${AUTH_ARGS[@]}" \
  -d 'secret=metadata+test+secret&ttl=300' \
  "${BASE_URL}/api/v1/share" 2>/dev/null)

METADATA_KEY2=$(echo "$CREATE_RESP2" | jq -r '.metadata_key // empty' 2>/dev/null)

if [[ -n "$METADATA_KEY2" ]]; then
  # GET /private/:key
  capture "40-private-get" GET "/private/${METADATA_KEY2}"

  # POST /private/:key
  capture "41-private-post" POST "/private/${METADATA_KEY2}"

  # GET /metadata/:key (alias)
  capture "42-metadata-get" GET "/metadata/${METADATA_KEY2}"

  # POST /metadata/:key (alias)
  capture "43-metadata-post" POST "/metadata/${METADATA_KEY2}"

  # GET /receipt/:key (new in v0.24)
  capture "44-receipt-get" GET "/receipt/${METADATA_KEY2}"

  # POST /receipt/:key (new in v0.24)
  capture "45-receipt-post" POST "/receipt/${METADATA_KEY2}"
else
  echo "  [SKIP] Could not create secret for metadata tests"
fi

# Non-existent metadata
capture "46-private-nonexistent" GET "/private/nonexistent_metadata_key"
capture "47-metadata-nonexistent" GET "/metadata/nonexistent_metadata_key"

# ── 6. Recent Metadata ──

echo "--- Recent Metadata ---"
capture "50-private-recent" GET "/private/recent"
capture "51-metadata-recent" GET "/metadata/recent"
capture "52-receipt-recent" GET "/receipt/recent"

# ── 7. Burn ──

echo "--- Burn ---"

# Create a secret to burn
CREATE_RESP3=$(curl -s -X POST \
  -H "Accept: application/json" \
  "${AUTH_ARGS[@]}" \
  -d 'secret=burn+test+secret&ttl=300' \
  "${BASE_URL}/api/v1/share" 2>/dev/null)

METADATA_KEY3=$(echo "$CREATE_RESP3" | jq -r '.metadata_key // empty' 2>/dev/null)

if [[ -n "$METADATA_KEY3" ]]; then
  # Burn via /private/:key/burn
  capture "60-burn-private" POST "/private/${METADATA_KEY3}/burn"

  # Try to access metadata after burn
  capture "61-metadata-after-burn" GET "/private/${METADATA_KEY3}"
else
  echo "  [SKIP] Could not create secret for burn tests"
fi

# Create another to burn via /receipt path
CREATE_RESP4=$(curl -s -X POST \
  -H "Accept: application/json" \
  "${AUTH_ARGS[@]}" \
  -d 'secret=burn+test+secret+2&ttl=300' \
  "${BASE_URL}/api/v1/share" 2>/dev/null)

METADATA_KEY4=$(echo "$CREATE_RESP4" | jq -r '.metadata_key // empty' 2>/dev/null)

if [[ -n "$METADATA_KEY4" ]]; then
  capture "62-burn-receipt" POST "/receipt/${METADATA_KEY4}/burn"
else
  echo "  [SKIP] Could not create secret for receipt burn test"
fi

# Burn non-existent
capture "63-burn-nonexistent" POST "/private/nonexistent_burn_key/burn"

# ── 8. Passphrase-Protected Secrets ──

echo "--- Passphrase Protected ---"

CREATE_RESP5=$(curl -s -X POST \
  -H "Accept: application/json" \
  "${AUTH_ARGS[@]}" \
  -d 'secret=passphrase+protected+secret&ttl=300&passphrase=correct-horse-battery' \
  "${BASE_URL}/api/v1/share" 2>/dev/null)

SECRET_KEY5=$(echo "$CREATE_RESP5" | jq -r '.secret_key // empty' 2>/dev/null)
METADATA_KEY5=$(echo "$CREATE_RESP5" | jq -r '.metadata_key // empty' 2>/dev/null)

if [[ -n "$SECRET_KEY5" ]]; then
  # Try to reveal without passphrase
  capture "70-reveal-no-passphrase" POST "/secret/${SECRET_KEY5}" \
    -H "Content-Type: application/json" \
    -d '{"continue":"true"}'

  # Try with wrong passphrase
  capture "71-reveal-wrong-passphrase" POST "/secret/${SECRET_KEY5}" \
    -H "Content-Type: application/json" \
    -d '{"continue":"true","passphrase":"wrong-pass"}'

  # Correct passphrase
  capture "72-reveal-correct-passphrase" POST "/secret/${SECRET_KEY5}" \
    -H "Content-Type: application/json" \
    -d '{"continue":"true","passphrase":"correct-horse-battery"}'

  # Metadata should show passphrase_required
  if [[ -n "$METADATA_KEY5" ]]; then
    capture "73-metadata-shows-passphrase" GET "/private/${METADATA_KEY5}"
  fi
else
  echo "  [SKIP] Could not create passphrase-protected secret"
fi

# ── 9. Auth Edge Cases ──

echo "--- Auth Edge Cases ---"

# Bad credentials (override auth args for this test)
SAVE_AUTH=("${AUTH_ARGS[@]}")
AUTH_ARGS=(-u "baduser@example.com:invalidtoken")
capture "80-bad-credentials" GET "/authcheck"
capture "81-bad-auth-share" POST "/share" \
  -H "Content-Type: application/json" \
  -d '{"secret":"should fail","ttl":300}'
AUTH_ARGS=("${SAVE_AUTH[@]}")

# No auth at all
SAVE_AUTH2=("${AUTH_ARGS[@]}")
AUTH_ARGS=()
capture "82-no-auth-status" GET "/status"
capture "83-no-auth-share" POST "/share" \
  -H "Content-Type: application/json" \
  -d '{"secret":"anonymous test","ttl":300}'
capture "84-no-auth-authcheck" GET "/authcheck"
AUTH_ARGS=("${SAVE_AUTH2[@]}")

# ── 10. Content-Type Handling ──

echo "--- Content-Type Handling ---"

# Form-encoded instead of JSON
capture "90-form-encoded-share" POST "/share" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d 'secret=form+encoded+secret&ttl=300'

# No content-type header
capture "91-no-content-type" POST "/share" \
  --data-raw '{"secret":"no content type","ttl":300}'

# ── Summary ──

echo ""
echo "=== Capture Complete ==="
TOTAL=$(find "$RUN_DIR" -name "*.json" | wc -l)
echo "Captured $TOTAL test cases in $RUN_DIR"
echo ""
echo "Next: run against both v0.23.6 and v0.24.0, then diff with:"
echo "  ./v1-diff.sh $RUN_DIR <other_run_dir>"
