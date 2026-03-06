#!/usr/bin/env bash
#
# run-all.sh — Full V1 API validation pipeline.
#
# Usage:
#   ./run-all.sh <v023_url> <v024_url> <username> <apitoken>
#
# Example:
#   ./run-all.sh http://localhost:3000 http://localhost:3001 user@example.com abc123
#
# Steps:
#   1. Capture responses from v0.23.4 instance
#   2. Capture responses from v0.24.0 instance
#   3. Diff the captures (black-box comparison)
#   4. Run static schema comparison (Zod vs Ruby)
#   5. Run Zod extraction + cross-reference
#
# Requirements: bash, curl, jq, node/npx (for TypeScript scripts)

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

echo "╔══════════════════════════════════════════════╗"
echo "║    OTS V1 API Validation Pipeline            ║"
echo "╠══════════════════════════════════════════════╣"
echo "║ v0.23.4: $V023_URL"
echo "║ v0.24.0: $V024_URL"
echo "║ Auth:    $USERNAME"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── Step 1: Capture v0.23.4 ──

echo "━━━ Step 1: Capturing v0.23.4 responses ━━━"
bash "$SCRIPT_DIR/v1-capture.sh" "$V023_URL" "$CAPTURES_DIR/v0.23.4" "$USERNAME" "$APITOKEN"
V023_RUN=$(ls -t "$CAPTURES_DIR/v0.23.4/" | head -1)
echo ""

# ── Step 2: Capture v0.24.0 ──

echo "━━━ Step 2: Capturing v0.24.0 responses ━━━"
bash "$SCRIPT_DIR/v1-capture.sh" "$V024_URL" "$CAPTURES_DIR/v0.24.0" "$USERNAME" "$APITOKEN"
V024_RUN=$(ls -t "$CAPTURES_DIR/v0.24.0/" | head -1)
echo ""

# ── Step 3: Diff captures ──

echo "━━━ Step 3: Diffing captures (black-box) ━━━"
bash "$SCRIPT_DIR/v1-diff.sh" \
  "$CAPTURES_DIR/v0.23.4/$V023_RUN" \
  "$CAPTURES_DIR/v0.24.0/$V024_RUN" \
  "$DIFFS_DIR/capture-diff.json" || true  # Don't exit on diff failures
echo ""

# ── Step 4: Static schema comparison ──

echo "━━━ Step 4: Static schema comparison ━━━"
cd "$SCRIPT_DIR"
npx tsx v1-schema-extract.ts \
  "$CAPTURES_DIR/v0.23.4/$V023_RUN" \
  "$DIFFS_DIR/schema-comparison.json" 2>/dev/null || {
    echo "  [WARN] TypeScript schema comparison failed. Ensure tsx is available: npm install -g tsx"
  }
echo ""

# ── Step 5: Zod extraction (needs gh CLI) ──

echo "━━━ Step 5: Zod vs Ruby extraction ━━━"
if command -v gh &>/dev/null; then
  npx tsx v1-zod-diff.ts "$DIFFS_DIR/zod-ruby-diff.json" 2>/dev/null || {
    echo "  [WARN] Zod extraction failed. Ensure gh CLI is authenticated."
  }
else
  echo "  [SKIP] gh CLI not available. Skipping remote schema extraction."
fi
echo ""

# ── Summary ──

echo "╔══════════════════════════════════════════════╗"
echo "║    Validation Complete                       ║"
echo "╠══════════════════════════════════════════════╣"
echo "║ Captures:                                    ║"
echo "║   v0.23.4: $CAPTURES_DIR/v0.23.4/$V023_RUN"
echo "║   v0.24.0: $CAPTURES_DIR/v0.24.0/$V024_RUN"
echo "║                                              ║"
echo "║ Reports:                                     ║"
echo "║   $DIFFS_DIR/capture-diff.json"
echo "║   $DIFFS_DIR/schema-comparison.json"
echo "║   $DIFFS_DIR/zod-ruby-diff.json"
echo "╚══════════════════════════════════════════════╝"
echo ""

# Quick summary from capture diff
if [[ -f "$DIFFS_DIR/capture-diff.json" ]]; then
  echo "Capture diff summary:"
  jq -r '.summary | "  Total: \(.total) | Pass: \(.pass) | Fail: \(.fail) | Missing: \(.missing)"' \
    "$DIFFS_DIR/capture-diff.json"

  FAIL_COUNT=$(jq '.summary.fail' "$DIFFS_DIR/capture-diff.json")
  if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    jq -r '.results[] | select(.status == "FAIL") | "  \(.test): \(.issues | join("; "))"' \
      "$DIFFS_DIR/capture-diff.json"
  fi
fi
