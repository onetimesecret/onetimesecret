#!/bin/bash
#
# Aggregate RSpec JSON test results into a unified report.
#
# Searches for RSpec JSON result files in the specified directory and
# combines them into a single unified-report.json with summary statistics.
#
# Usage:
#   ./aggregate-test-results.sh [results-dir]
#
# Arguments:
#   results-dir  Directory containing test result JSON files (default: test-results)
#
# Outputs (to GITHUB_OUTPUT if set):
#   has_results=true|false
#   total_examples=<number>
#   total_failures=<number>
#   total_pending=<number>
#   unreadable_files=<number>
#
# Creates:
#   <results-dir>/unified-report.json
#
# A results file that is empty or is not a JSON object is left out of the
# totals and named: in a ::warning:: annotation, in `unreadable_files` in the
# report, and in the count above. rspec truncates its --out file when it
# opens it, so a test process that stops before it writes its results leaves
# a 0-byte file behind. Read as "no input", such a file used to lower the
# totals with nothing on this job saying so.

set -e

RESULTS_DIR="${1:-test-results}"

mkdir -p "$RESULTS_DIR"

# Find all RSpec JSON result files
# Match patterns: rspec_*.json, *_results.json
READABLE=()
UNREADABLE=()
while IFS= read -r -d '' file; do
  if [ -s "$file" ] && jq -e 'type == "object"' "$file" > /dev/null 2>&1; then
    READABLE+=("$file")
  else
    UNREADABLE+=("$file")
  fi
done < <(find "$RESULTS_DIR" -type f \( -name "rspec_*.json" -o -name "*_results.json" \) -print0 2> /dev/null | sort -z)

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
UNREADABLE_JSON='[]'
if [ "${#UNREADABLE[@]}" -gt 0 ]; then
  UNREADABLE_JSON=$(printf '%s\n' "${UNREADABLE[@]}" | jq -R . | jq -s -c .)
  for file in "${UNREADABLE[@]}"; do
    echo "::warning::RSpec results file ${file} is empty or is not JSON; the totals leave it out. The test process stopped before it wrote its results."
  done
fi

write_empty_report() { # <reason>
  jq -n --arg reason "$1" --arg timestamp "$TIMESTAMP" --argjson unreadable "$UNREADABLE_JSON" \
    '{aggregated: false, reason: $reason, timestamp: $timestamp, unreadable_files: $unreadable}' \
    > "$RESULTS_DIR/unified-report.json"

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "has_results=false"
      echo "unreadable_files=${#UNREADABLE[@]}"
    } >> "$GITHUB_OUTPUT"
  fi
}

if [ "${#READABLE[@]}" -eq 0 ] && [ "${#UNREADABLE[@]}" -eq 0 ]; then
  echo "::notice::No RSpec result files found to aggregate"
  write_empty_report no_files_found
  exit 0
fi

if [ "${#READABLE[@]}" -eq 0 ]; then
  echo "::notice::No readable RSpec result files to aggregate (${#UNREADABLE[@]} empty or not JSON)"
  write_empty_report no_readable_files
  exit 0
fi

echo "Found result files:"
printf '%s\n' "${READABLE[@]}"

# Aggregate all RSpec JSON files into unified report
# Structure: { summary: {...}, files: [...], failures: [...], timestamp: "..." }
jq -s --argjson unreadable "$UNREADABLE_JSON" '
  {
    aggregated: true,
    timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
    summary: {
      total_examples: (map(.summary.example_count // 0) | add),
      total_failures: (map(.summary.failure_count // 0) | add),
      total_pending: (map(.summary.pending_count // 0) | add),
      total_errors: (map(.summary.errors_outside_of_examples_count // 0) | add),
      total_duration: (map(.summary.duration // 0) | add),
      file_count: length,
      unreadable_file_count: ($unreadable | length)
    },
    files: [.[] | {
      file: (.summary.seed // "unknown"),
      examples: (.summary.example_count // 0),
      failures: (.summary.failure_count // 0),
      pending: (.summary.pending_count // 0),
      duration: (.summary.duration // 0)
    }],
    failures: [.[] | .examples[]? | select(.status == "failed") | {
      id: .id,
      description: .full_description,
      file: .file_path,
      line: .line_number,
      message: .exception.message?
    }],
    unreadable_files: $unreadable
  }
' "${READABLE[@]}" > "$RESULTS_DIR/unified-report.json"

# Extract summary for outputs
TOTAL=$(jq '.summary.total_examples' "$RESULTS_DIR/unified-report.json")
FAILURES=$(jq '.summary.total_failures' "$RESULTS_DIR/unified-report.json")
PENDING=$(jq '.summary.total_pending' "$RESULTS_DIR/unified-report.json")

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "has_results=true"
    echo "total_examples=$TOTAL"
    echo "total_failures=$FAILURES"
    echo "total_pending=$PENDING"
    echo "unreadable_files=${#UNREADABLE[@]}"
  } >> "$GITHUB_OUTPUT"
else
  # Local testing - print to stdout
  echo "has_results=true"
  echo "total_examples=$TOTAL"
  echo "total_failures=$FAILURES"
  echo "total_pending=$PENDING"
  echo "unreadable_files=${#UNREADABLE[@]}"
fi

NOTE=""
if [ "${#UNREADABLE[@]}" -gt 0 ]; then
  NOTE="; ${#UNREADABLE[@]} results file(s) empty or not JSON, left out"
fi
echo "::notice::Aggregated $TOTAL examples ($FAILURES failures, $PENDING pending)${NOTE}"
