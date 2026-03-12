#!/usr/bin/env bash
#
# v2-diff.sh — Compare two V2 capture runs and produce a structured diff report.
#
# Usage:
#   ./v2-diff.sh <baseline_dir> <candidate_dir> [output_file]
#
# Example:
#   ./v2-diff.sh ./captures/v0.24.0-v2/20260217-120000 ./captures/v0.25.0-v2/20260217-120500
#   ./v2-diff.sh ./captures/baseline ./captures/candidate ./diffs/my-report.json
#
# Compares each test case across both runs and flags:
#   - Status code changes
#   - Content-type header changes
#   - Response body field additions/removals/type changes (recursive, with dotted paths)
#   - Semantic value changes in non-dynamic fields
#   - Legacy V1 vocabulary appearing in V2 candidate responses (warnings)
#
# Requirements: jq

set -euo pipefail

BASELINE_DIR="${1:?Usage: $0 <baseline_dir> <candidate_dir> [output_file]}"
CANDIDATE_DIR="${2:?Usage: $0 <baseline_dir> <candidate_dir> [output_file]}"
OUTPUT_FILE="${3:-./diffs/v2-diff-report.json}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

# ─── jq Filters (defined once, reused per test) ─────────────────────────

# Recursive body comparison with full dotted-path output.
# Inputs: $b (baseline body), $c (candidate body)
# Walks both trees, skipping dynamic fields, producing:
#   fields_only_in_baseline, fields_only_in_candidate, type_changes, value_changes
#   — all with fully qualified dotted paths.
COMPARE_BODIES_FILTER='
# Dynamic fields that change per-request and should be ignored for value comparison
def is_dynamic:
  test("(^|\\.)(__v|identifier|shortid|secret_identifier|secret_shortid|updated|created|shared|previewed|revealed|burned|custid|owner_id|run_id)$");

# Recursively collect all leaf paths as dotted strings, paired with their types and values
def leaf_paths(prefix):
  if type == "object" then
    to_entries | map(
      (if prefix == "" then .key else prefix + "." + .key end) as $p |
      if (.value | type) == "object" then
        .value | leaf_paths($p)
      elif (.value | type) == "array" then
        [{path: $p, typ: "array", val: .value}]
      else
        [{path: $p, typ: (.value | type), val: .value}]
      end
    ) | flatten
  elif type == "array" then
    [{path: (if prefix == "" then "(root)" else prefix end), typ: "array", val: .}]
  else
    [{path: (if prefix == "" then "(root)" else prefix end), typ: type, val: .}]
  end;

# Recursively collect all key paths (including intermediate object nodes)
def all_key_paths(prefix):
  if type == "object" then
    to_entries | map(
      (if prefix == "" then .key else prefix + "." + .key end) as $p |
      [{path: $p, typ: (.value | type)}] +
      if (.value | type) == "object" then
        .value | all_key_paths($p)
      else
        []
      end
    ) | flatten
  else
    []
  end;

($b | leaf_paths("")) as $b_leaves |
($c | leaf_paths("")) as $c_leaves |

# Build lookup maps: path -> {typ, val}
($b_leaves | map({(.path): {typ: .typ, val: .val}}) | add // {}) as $b_map |
($c_leaves | map({(.path): {typ: .typ, val: .val}}) | add // {}) as $c_map |

($b_leaves | map(.path)) as $b_paths |
($c_leaves | map(.path)) as $c_paths |

# Also collect intermediate object paths so we can detect structural additions/removals
($b | all_key_paths("") | map(.path)) as $b_all_keys |
($c | all_key_paths("") | map(.path)) as $c_all_keys |

# Combine leaf + intermediate for full structural comparison
(($b_paths + $b_all_keys) | unique) as $b_full |
(($c_paths + $c_all_keys) | unique) as $c_full |

{
  fields_only_in_baseline: (
    [$b_full[] | select(. as $p | $c_full | index($p) | not)]
    # Filter out parent paths whose children are already listed
    | . as $removed |
      [.[] | select(. as $p |
        $removed | map(select(startswith($p + ".") and . != $p)) | length == 0
      )]
  ),

  fields_only_in_candidate: (
    [$c_full[] | select(. as $p | $b_full | index($p) | not)]
    | . as $added |
      [.[] | select(. as $p |
        $added | map(select(startswith($p + ".") and . != $p)) | length == 0
      )]
  ),

  type_changes: [
    $b_paths[] | select(. as $p | $c_paths | index($p)) |
    . as $p |
    select($b_map[$p].typ != $c_map[$p].typ) |
    {path: $p, baseline_type: $b_map[$p].typ, candidate_type: $c_map[$p].typ}
  ],

  value_changes: [
    $b_paths[] | select(. as $p | $c_paths | index($p)) |
    . as $p |
    select(
      $b_map[$p].typ == $c_map[$p].typ and
      ($b_map[$p].typ != "object") and
      ($b_map[$p].typ != "array") and
      $b_map[$p].val != $c_map[$p].val and
      ($p | is_dynamic | not)
    ) |
    {path: $p, baseline: $b_map[$p].val, candidate: $c_map[$p].val}
  ]
}
'

# Legacy V1 vocabulary check.
# These field names should NOT appear in V2 responses per the compat policy.
# Presence is flagged as WARNING, not FAIL.
LEGACY_VOCAB_FILTER='
def legacy_field_paths(prefix):
  if type == "object" then
    to_entries | map(
      (if prefix == "" then .key else prefix + "." + .key end) as $p |
      (
        if (.key == "metadata_key" or .key == "secret_key" or .key == "passphrase_required") then
          [{path: $p, field: .key}]
        elif (.key == "value" and prefix == "") then
          [{path: $p, field: "value (top-level)"}]
        elif (.key == "viewed" and (.value | type) == "number") then
          [{path: $p, field: "viewed (timestamp)"}]
        elif (.key == "received" and (.value | type) == "number") then
          [{path: $p, field: "received (timestamp)"}]
        else
          []
        end
      ) +
      if (.value | type) == "object" then
        .value | legacy_field_paths($p)
      else
        []
      end
    ) | flatten
  else
    []
  end;

legacy_field_paths("")
'

# ─── Main Loop ─────────────────────────────────────────────────────────

echo "=== V2 API Diff Report ==="
echo "Baseline:  $BASELINE_DIR"
echo "Candidate: $CANDIDATE_DIR"
echo ""

RESULTS="[]"
TOTAL=0
PASS=0
FAIL=0
WARN=0
MISSING=0

for baseline_file in "$BASELINE_DIR"/*.json; do
  test_name=$(basename "$baseline_file" .json)
  candidate_file="$CANDIDATE_DIR/${test_name}.json"
  TOTAL=$((TOTAL + 1))

  if [[ ! -f "$candidate_file" ]]; then
    echo "  [MISSING] $test_name -- no candidate capture"
    MISSING=$((MISSING + 1))
    RESULTS=$(echo "$RESULTS" | jq \
      --arg name "$test_name" \
      '. + [{test: $name, status: "MISSING", issues: ["No candidate capture found"], warnings: []}]')
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
  warnings="[]"

  # ── Status code comparison ──
  if [[ "$b_status" != "$c_status" ]]; then
    issues=$(echo "$issues" | jq \
      --arg bs "$b_status" --arg cs "$c_status" \
      '. + ["Status code changed: \($bs) -> \($cs)"]')
  fi

  # ── Content-type comparison ──
  if [[ "$b_ct" != "$c_ct" ]]; then
    issues=$(echo "$issues" | jq \
      --arg bct "$b_ct" --arg cct "$c_ct" \
      '. + ["Content-Type changed: \($bct) -> \($cct)"]')
  fi

  # ── Recursive body comparison ──
  body_diff=$(jq -n \
    --argjson b "$b_body" \
    --argjson c "$c_body" \
    "$COMPARE_BODIES_FILTER" 2>/dev/null || echo '{"error": "comparison failed"}')

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
    type_list=$(echo "$body_diff" | jq -r '.type_changes | map("\(.path): \(.baseline_type)->\(.candidate_type)") | join(", ")')
    issues=$(echo "$issues" | jq \
      --arg t "$type_list" \
      '. + ["Field type changes: \($t)"]')
  fi

  if [[ "$value_changes" -gt 0 ]]; then
    val_list=$(echo "$body_diff" | jq -r '.value_changes | map("\(.path): \(.baseline)->\(.candidate)") | join(", ")')
    issues=$(echo "$issues" | jq \
      --arg v "$val_list" \
      '. + ["Semantic value changes: \($v)"]')
  fi

  # ── Legacy vocabulary check (candidate only) ──
  legacy_hits=$(echo "$c_body" | jq "$LEGACY_VOCAB_FILTER" 2>/dev/null || echo '[]')
  legacy_count=$(echo "$legacy_hits" | jq 'length')

  if [[ "$legacy_count" -gt 0 ]]; then
    legacy_list=$(echo "$legacy_hits" | jq -r 'map("\(.field) at \(.path)") | join(", ")')
    warnings=$(echo "$warnings" | jq \
      --arg l "$legacy_list" \
      '. + ["Legacy V1 vocabulary in candidate: \($l)"]')
  fi

  # ── Determine test result ──
  issue_count=$(echo "$issues" | jq 'length')
  warning_count=$(echo "$warnings" | jq 'length')

  if [[ "$issue_count" -gt 0 ]]; then
    status="FAIL"
    FAIL=$((FAIL + 1))
    label="[FAIL] $test_name ($issue_count issues)"
  elif [[ "$warning_count" -gt 0 ]]; then
    status="WARN"
    WARN=$((WARN + 1))
    label="[WARN] $test_name ($warning_count warnings)"
  else
    status="PASS"
    PASS=$((PASS + 1))
    label="[PASS] $test_name"
  fi

  echo "  $label"

  RESULTS=$(echo "$RESULTS" | jq \
    --arg name "$test_name" \
    --arg stat "$status" \
    --argjson issues "$issues" \
    --argjson warnings "$warnings" \
    --argjson body_diff "$body_diff" \
    --argjson legacy "$legacy_hits" \
    '. + [{
      test: $name,
      status: $stat,
      issues: $issues,
      warnings: $warnings,
      body_diff: $body_diff,
      legacy_vocabulary: $legacy
    }]')

done

# ─── Summary Report ────────────────────────────────────────────────────

SUMMARY=$(jq -n \
  --arg baseline "$BASELINE_DIR" \
  --arg candidate "$CANDIDATE_DIR" \
  --argjson total "$TOTAL" \
  --argjson pass "$PASS" \
  --argjson warn "$WARN" \
  --argjson fail "$FAIL" \
  --argjson missing "$MISSING" \
  --argjson results "$RESULTS" \
  '{
    summary: {
      baseline: $baseline,
      candidate: $candidate,
      total: $total,
      pass: $pass,
      warn: $warn,
      fail: $fail,
      missing: $missing,
      generated: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
    },
    results: $results
  }')

echo "$SUMMARY" > "$OUTPUT_FILE"

echo ""
echo "=== Summary ==="
echo "Total: $TOTAL | Pass: $PASS | Warn: $WARN | Fail: $FAIL | Missing: $MISSING"
echo "Report: $OUTPUT_FILE"

# Exit with failure if any FAIL results (warnings do not cause failure)
if [[ "$FAIL" -gt 0 || "$MISSING" -gt 0 ]]; then
  exit 1
fi
