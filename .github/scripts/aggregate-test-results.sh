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
#
# Creates:
#   <results-dir>/unified-report.json

set -e

RESULTS_DIR="${1:-test-results}"

mkdir -p "$RESULTS_DIR"

# Find all RSpec JSON result files
# Match patterns: rspec_*.json, *_results.json
RSPEC_FILES=$(find "$RESULTS_DIR" -name "rspec_*.json" -o -name "*_results.json" 2>/dev/null || true)

if [ -z "$RSPEC_FILES" ]; then
  echo "::notice::No RSpec result files found to aggregate"
  TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "{\"aggregated\": false, \"reason\": \"no_files_found\", \"timestamp\": \"$TIMESTAMP\"}" > "$RESULTS_DIR/unified-report.json"

  if [[ -n "$GITHUB_OUTPUT" ]]; then
    echo "has_results=false" >> "$GITHUB_OUTPUT"
  fi
  exit 0
fi

echo "Found result files:"
echo "$RSPEC_FILES"

# Aggregate all RSpec JSON files into unified report
# Structure: { summary: {...}, files: [...], failures: [...], timestamp: "..." }
# shellcheck disable=SC2086
jq -s '
  {
    aggregated: true,
    timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
    summary: {
      total_examples: (map(.summary.example_count // 0) | add),
      total_failures: (map(.summary.failure_count // 0) | add),
      total_pending: (map(.summary.pending_count // 0) | add),
      total_errors: (map(.summary.errors_outside_of_examples_count // 0) | add),
      total_duration: (map(.summary.duration // 0) | add),
      file_count: length
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
    }]
  }
' $RSPEC_FILES > "$RESULTS_DIR/unified-report.json"

# Extract summary for outputs
TOTAL=$(jq '.summary.total_examples' "$RESULTS_DIR/unified-report.json")
FAILURES=$(jq '.summary.total_failures' "$RESULTS_DIR/unified-report.json")
PENDING=$(jq '.summary.total_pending' "$RESULTS_DIR/unified-report.json")

if [[ -n "$GITHUB_OUTPUT" ]]; then
  echo "has_results=true" >> "$GITHUB_OUTPUT"
  echo "total_examples=$TOTAL" >> "$GITHUB_OUTPUT"
  echo "total_failures=$FAILURES" >> "$GITHUB_OUTPUT"
  echo "total_pending=$PENDING" >> "$GITHUB_OUTPUT"
else
  # Local testing - print to stdout
  echo "has_results=true"
  echo "total_examples=$TOTAL"
  echo "total_failures=$FAILURES"
  echo "total_pending=$PENDING"
fi

echo "::notice::Aggregated $TOTAL examples ($FAILURES failures, $PENDING pending)"
