#!/bin/bash
#
# Generate GitHub Job Summary from unified test report.
#
# Reads the unified-report.json and generates a markdown summary
# with test statistics and failure details.
#
# Usage:
#   ./generate-test-summary.sh [report-path]
#
# Arguments:
#   report-path  Path to unified-report.json (default: test-results/unified-report.json)
#
# Outputs:
#   Appends markdown to GITHUB_STEP_SUMMARY (or stdout for local testing)

set -e

REPORT_PATH="${1:-test-results/unified-report.json}"

# Use GITHUB_STEP_SUMMARY if set, otherwise stdout
SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

# Start summary
{
  echo "## Test Results Summary"
  echo ""
} >> "$SUMMARY_FILE"

if [ ! -f "$REPORT_PATH" ]; then
  echo "> :warning: unified-report.json not generated" >> "$SUMMARY_FILE"
  exit 0
fi

AGGREGATED=$(jq -r '.aggregated' "$REPORT_PATH")

if [ "$AGGREGATED" != "true" ]; then
  REASON=$(jq -r '.reason' "$REPORT_PATH")
  echo "> :grey_question: No test results to aggregate ($REASON)" >> "$SUMMARY_FILE"
  exit 0
fi

# Extract metrics
TOTAL=$(jq '.summary.total_examples' "$REPORT_PATH")
FAILURES=$(jq '.summary.total_failures' "$REPORT_PATH")
PENDING=$(jq '.summary.total_pending' "$REPORT_PATH")
DURATION=$(jq '.summary.total_duration' "$REPORT_PATH")
FILE_COUNT=$(jq '.summary.file_count' "$REPORT_PATH")

# Determine status icon
if [ "$FAILURES" -eq 0 ]; then
  STATUS_ICON=":white_check_mark:"
else
  STATUS_ICON=":x:"
fi

# Generate summary table
{
  echo "| Metric | Value |"
  echo "|--------|-------|"
  echo "| Status | $STATUS_ICON |"
  echo "| Total Examples | $TOTAL |"
  echo "| Failures | $FAILURES |"
  echo "| Pending | $PENDING |"
  echo "| Duration | ${DURATION}s |"
  echo "| Result Files | $FILE_COUNT |"
} >> "$SUMMARY_FILE"

# Show failures if any
if [ "$FAILURES" -gt 0 ]; then
  {
    echo ""
    echo "### Failed Tests"
    echo ""
  } >> "$SUMMARY_FILE"

  # Extract and format first 10 failures
  jq -r '.failures[:10][] | "- **\(.description)**\n  - File: `\(.file):\(.line)`\n  - Message: \(.message // "N/A" | split("\n")[0])"' "$REPORT_PATH" >> "$SUMMARY_FILE"

  if [ "$FAILURES" -gt 10 ]; then
    REMAINING=$((FAILURES - 10))
    echo "" >> "$SUMMARY_FILE"
    echo "_... and $REMAINING more failures (see unified-report.json artifact)_" >> "$SUMMARY_FILE"
  fi
fi
