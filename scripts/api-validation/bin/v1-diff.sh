#!/usr/bin/env bash
#
# v1-diff.sh — Compare two capture runs and produce a structured diff report.
#
# Usage:
#   ./v1-diff.sh <baseline_dir> <candidate_dir> [output_file]
#
# Example:
#   ./v1-diff.sh ./captures/v0.23.6/20260217-120000 ./captures/v0.24.0/20260217-120500 ./diffs/report.json
#
# Compares each test case across both runs and flags:
#   - Status code changes
#   - Response body field additions/removals/type changes
#   - Header changes (content-type, cache-control, etc.)
#   - Value changes in key fields (state, ttl, etc.)
#
# Requirements: jq

set -euo pipefail

BASELINE_DIR="${1:?Usage: $0 <baseline_dir> <candidate_dir> [output_file]}"
CANDIDATE_DIR="${2:?Usage: $0 <baseline_dir> <candidate_dir> [output_file]}"
OUTPUT_FILE="${3:-./diffs/v1-diff-report.json}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

# ─── Helpers ───────────────────────────────────────────────────────────

# Extract field names and types from a JSON object (one level deep)
field_signature() {
  local json="$1"
  echo "$json" | jq -r '
    if type == "object" then
      to_entries | map("\(.key):\(.value | type)") | sort | .[]
    elif type == "array" then
      "array:" + (length | tostring)
    else
      type
    end
  ' 2>/dev/null || echo "unparseable"
}

# Deep field comparison
compare_bodies() {
  local baseline="$1"
  local candidate="$2"

  jq -n \
    --argjson b "$baseline" \
    --argjson c "$candidate" \
    '
    def field_types:
      if type == "object" then
        to_entries | map({key: .key, type: (.value | type)}) | from_entries
      else
        {_root: type}
      end;

    def deep_keys(prefix):
      if type == "object" then
        to_entries | map(
          if .value | type == "object" then
            .value | deep_keys(prefix + .key + ".")
          else
            [prefix + .key]
          end
        ) | flatten
      else
        [prefix + "(value)"]
      end;

    # Fields intentionally removed in v0.24 (not regressions)
    ["shrimp"] as $ignored_fields |

    ($b | if type == "object" then keys | map(select(. as $k | $ignored_fields | index($k) | not)) else [] end) as $bkeys |
    ($c | if type == "object" then keys | map(select(. as $k | $ignored_fields | index($k) | not)) else [] end) as $ckeys |

    {
      fields_only_in_baseline: ($bkeys - $ckeys),
      fields_only_in_candidate: ($ckeys - $bkeys),
      fields_in_both: ($bkeys | map(select(. as $k | $ckeys | index($k)))),
      type_changes: (
        ($bkeys | map(select(. as $k | $ckeys | index($k)))) |
        map(. as $k |
          {
            key: $k,
            baseline_type: ($b[$k] | type),
            candidate_type: ($c[$k] | type)
          }
        ) |
        map(select(.baseline_type != .candidate_type))
      ),
      value_changes: (
        ($bkeys | map(select(. as $k | $ckeys | index($k)))) |
        map(. as $k |
          select(
            ($b[$k] | type) == ($c[$k] | type) and
            ($b[$k] | type) != "object" and
            ($b[$k] | type) != "array" and
            $b[$k] != $c[$k] and
            # Skip dynamic fields that will always differ between captures:
            #   identifiers/keys: unique per secret creation
            #   value/secret_value: random for /generate, consumed on reveal
            #   received: timestamp set at reveal time
            #   updated/created: timestamps
            (["updated","created","shrimp","secret_key","metadata_key","identifier","key","shortid","secret_shortid","secret_identifier","value","secret_value","received"] | index($k) | not) and
            # Numeric tolerance: skip near-equal numbers (timing drift between captures)
            (if ($b[$k] | type) == "number" and ($c[$k] | type) == "number" then
              (($b[$k] - $c[$k]) | if . < 0 then -. else . end) > 10
            else
              true
            end)
          ) |
          {
            key: $k,
            baseline: $b[$k],
            candidate: $c[$k]
          }
        )
      )
    }
    ' 2>/dev/null || echo '{"error": "comparison failed"}'
}

# ─── Main Loop ─────────────────────────────────────────────────────────

echo "=== V1 API Diff Report ==="
echo "Baseline:  $BASELINE_DIR"
echo "Candidate: $CANDIDATE_DIR"
echo ""

RESULTS="[]"
TOTAL=0
PASS=0
FAIL=0
MISSING=0
EXTRA=0

for baseline_file in "$BASELINE_DIR"/*.json; do
  test_name=$(basename "$baseline_file" .json)
  candidate_file="$CANDIDATE_DIR/${test_name}.json"
  TOTAL=$((TOTAL + 1))

  if [[ ! -f "$candidate_file" ]]; then
    echo "  [MISSING] $test_name — no candidate capture"
    MISSING=$((MISSING + 1))
    RESULTS=$(echo "$RESULTS" | jq \
      --arg name "$test_name" \
      '. + [{test: $name, status: "missing", issues: ["No candidate capture found"]}]')
    continue
  fi

  # Extract response components
  b_status=$(jq -r '.response.status' "$baseline_file")
  c_status=$(jq -r '.response.status' "$candidate_file")
  b_body=$(jq '.response.body' "$baseline_file")
  c_body=$(jq '.response.body' "$candidate_file")
  b_ct=$(jq -r '.response.headers["content-type"] // "none"' "$baseline_file")
  c_ct=$(jq -r '.response.headers["content-type"] // "none"' "$candidate_file")

  issues="[]"

  # Status code comparison
  if [[ "$b_status" != "$c_status" ]]; then
    issues=$(echo "$issues" | jq \
      --arg bs "$b_status" --arg cs "$c_status" \
      '. + ["Status code changed: \($bs) -> \($cs)"]')
  fi

  # Content-type comparison
  if [[ "$b_ct" != "$c_ct" ]]; then
    issues=$(echo "$issues" | jq \
      --arg bct "$b_ct" --arg cct "$c_ct" \
      '. + ["Content-Type changed: \($bct) -> \($cct)"]')
  fi

  # Body comparison
  body_diff=$(compare_bodies "$b_body" "$c_body")

  removed_fields=$(echo "$body_diff" | jq -r '.fields_only_in_baseline | length')
  added_fields=$(echo "$body_diff" | jq -r '.fields_only_in_candidate | length')
  type_changes=$(echo "$body_diff" | jq -r '.type_changes | length')
  value_changes=$(echo "$body_diff" | jq -r '.value_changes | length')

  if [[ "$removed_fields" -gt 0 ]]; then
    removed_list=$(echo "$body_diff" | jq -r '.fields_only_in_baseline | join(", ")')
    issues=$(echo "$issues" | jq \
      --arg f "$removed_list" \
      '. + ["Fields removed from response: \($f)"]')
  fi

  if [[ "$added_fields" -gt 0 ]]; then
    added_list=$(echo "$body_diff" | jq -r '.fields_only_in_candidate | join(", ")')
    issues=$(echo "$issues" | jq \
      --arg f "$added_list" \
      '. + ["Fields added to response: \($f)"]')
  fi

  if [[ "$type_changes" -gt 0 ]]; then
    type_list=$(echo "$body_diff" | jq -r '.type_changes | map("\(.key): \(.baseline_type)->\(.candidate_type)") | join(", ")')
    issues=$(echo "$issues" | jq \
      --arg t "$type_list" \
      '. + ["Field type changes: \($t)"]')
  fi

  if [[ "$value_changes" -gt 0 ]]; then
    val_list=$(echo "$body_diff" | jq -r '.value_changes | map("\(.key): \(.baseline)->\(.candidate)") | join(", ")')
    issues=$(echo "$issues" | jq \
      --arg v "$val_list" \
      '. + ["Semantic value changes: \($v)"]')
  fi

  issue_count=$(echo "$issues" | jq 'length')
  if [[ "$issue_count" -gt 0 ]]; then
    status="FAIL"
    FAIL=$((FAIL + 1))
    echo "  [FAIL] $test_name ($issue_count issues)"
  else
    status="PASS"
    PASS=$((PASS + 1))
    echo "  [PASS] $test_name"
  fi

  RESULTS=$(echo "$RESULTS" | jq \
    --arg name "$test_name" \
    --arg stat "$status" \
    --argjson issues "$issues" \
    --argjson body_diff "$body_diff" \
    '. + [{
      test: $name,
      status: $stat,
      issues: $issues,
      body_diff: $body_diff
    }]')

done

# ─── Candidate-Only Tests ─────────────────────────────────────────────

for candidate_file in "$CANDIDATE_DIR"/*.json; do
  test_name=$(basename "$candidate_file" .json)
  baseline_file="$BASELINE_DIR/${test_name}.json"
  if [[ ! -f "$baseline_file" ]]; then
    echo "  [EXTRA] $test_name — candidate only (no baseline)"
    EXTRA=$((EXTRA + 1))
    RESULTS=$(echo "$RESULTS" | jq \
      --arg name "$test_name" \
      '. + [{test: $name, status: "extra", issues: ["Present in candidate but absent from baseline"]}]')
  fi
done

# ─── Summary Report ────────────────────────────────────────────────────

SUMMARY=$(jq -n \
  --arg baseline "$BASELINE_DIR" \
  --arg candidate "$CANDIDATE_DIR" \
  --argjson total "$TOTAL" \
  --argjson pass "$PASS" \
  --argjson fail "$FAIL" \
  --argjson missing "$MISSING" \
  --argjson extra "$EXTRA" \
  --argjson results "$RESULTS" \
  '{
    summary: {
      baseline: $baseline,
      candidate: $candidate,
      total: $total,
      pass: $pass,
      fail: $fail,
      missing: $missing,
      extra: $extra,
      generated: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
    },
    results: $results
  }')

echo "$SUMMARY" > "$OUTPUT_FILE"

echo ""
echo "=== Summary ==="
echo "Total: $TOTAL | Pass: $PASS | Fail: $FAIL | Missing: $MISSING | Extra: $EXTRA"
echo "Report: $OUTPUT_FILE"

# Exit with failure if any diffs found
if [[ "$FAIL" -gt 0 || "$MISSING" -gt 0 ]]; then
  exit 1
fi
