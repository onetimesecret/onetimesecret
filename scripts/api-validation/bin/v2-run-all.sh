#!/usr/bin/env bash
#
# v2-run-all.sh — Full V2 API validation pipeline.
#
# Usage:
#   ./v2-run-all.sh <v023_url> <v024_url> <username> <apitoken>
#
# Example:
#   ./v2-run-all.sh http://localhost:3000 http://localhost:3001 user@example.com abc123
#
# Steps:
#   1. Capture responses from v0.23.6 instance (V2 API)
#   2. Capture responses from v0.24.0 instance (V2 API)
#   3. Diff the captures (black-box comparison)
#
# Requirements: bash, curl, jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

V023_URL="${1:?Usage: $0 <v023_url> <v024_url> <username> <apitoken>}"
V024_URL="${2:?Usage: $0 <v023_url> <v024_url> <username> <apitoken>}"
USERNAME="${3:?Usage: $0 <v023_url> <v024_url> <username> <apitoken>}"
APITOKEN="${4:?Usage: $0 <v023_url> <v024_url> <username> <apitoken>}"

CAPTURES_DIR="$BASE_DIR/captures"
DIFFS_DIR="$BASE_DIR/diffs"
mkdir -p "$CAPTURES_DIR" "$DIFFS_DIR"

echo ""
echo "=============================================="
echo "    OTS V2 API Validation Pipeline"
echo "=============================================="
echo "  v0.23.6: $V023_URL"
echo "  v0.24.0: $V024_URL"
echo "  Auth:    $USERNAME"
echo "=============================================="
echo ""

# ── Step 1: Capture v0.23.6 (V2 API) ──

echo "--- Step 1: Capturing v0.23.6 V2 responses ---"
bash "$SCRIPT_DIR/v2-capture.sh" "$V023_URL" "$CAPTURES_DIR/v0.23.6-v2" "$USERNAME" "$APITOKEN"
V023_RUN=$(ls -t "$CAPTURES_DIR/v0.23.6-v2/" | head -1)
echo ""

# ── Step 2: Capture v0.24.0 (V2 API) ──

echo "--- Step 2: Capturing v0.24.0 V2 responses ---"
bash "$SCRIPT_DIR/v2-capture.sh" "$V024_URL" "$CAPTURES_DIR/v0.24.0-v2" "$USERNAME" "$APITOKEN"
V024_RUN=$(ls -t "$CAPTURES_DIR/v0.24.0-v2/" | head -1)
echo ""

# ── Step 3: Diff captures ──

echo "--- Step 3: Diffing V2 captures (black-box) ---"
bash "$SCRIPT_DIR/v2-diff.sh" \
  "$CAPTURES_DIR/v0.23.6-v2/$V023_RUN" \
  "$CAPTURES_DIR/v0.24.0-v2/$V024_RUN" \
  "$DIFFS_DIR/v2-capture-diff.json" || true  # Don't exit on diff failures
echo ""

# ── Summary ──

echo "=============================================="
echo "    Validation Complete"
echo "=============================================="
echo "  Captures:"
echo "    v0.23.6: $CAPTURES_DIR/v0.23.6-v2/$V023_RUN"
echo "    v0.24.0: $CAPTURES_DIR/v0.24.0-v2/$V024_RUN"
echo ""
echo "  Report:"
echo "    $DIFFS_DIR/v2-capture-diff.json"
echo "=============================================="
echo ""

# Quick summary from capture diff
if [[ -f "$DIFFS_DIR/v2-capture-diff.json" ]]; then
  echo "Capture diff summary:"
  jq -r '.summary | "  Total: \(.total) | Pass: \(.pass) | Warn: \(.warn) | Fail: \(.fail) | Missing: \(.missing)"' \
    "$DIFFS_DIR/v2-capture-diff.json"

  FAIL_COUNT=$(jq '.summary.fail' "$DIFFS_DIR/v2-capture-diff.json")
  if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    jq -r '.results[] | select(.status == "FAIL") | "  \(.test): \(.issues | join("; "))"' \
      "$DIFFS_DIR/v2-capture-diff.json"
  fi

  WARN_COUNT=$(jq '.summary.warn' "$DIFFS_DIR/v2-capture-diff.json")
  if [[ "$WARN_COUNT" -gt 0 ]]; then
    echo ""
    echo "Warnings (legacy V1 vocabulary):"
    jq -r '.results[] | select(.status == "WARN") | "  \(.test): \(.warnings | join("; "))"' \
      "$DIFFS_DIR/v2-capture-diff.json"
  fi
fi
