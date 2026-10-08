#!/usr/bin/env bash
#
# tools/testsuite/aggregate-test-results-test.sh
#
# Covers .github/scripts/aggregate-test-results.sh and the summary
# .github/scripts/generate-test-summary.sh renders from its report.
#
# WHAT THIS PROTECTS
#
# The aggregate job adds up the RSpec results every lane uploaded and puts
# the totals on the run page. rspec truncates its --out file when it opens
# it, so a test process that stops before it writes its results leaves a
# 0-byte file. Read as "no input", such a file lowered the totals and nothing
# on the aggregate job said so: a run that lost a third of its examples looked
# like a smaller run. A results file that is empty or is not JSON must be
# left out of the totals AND named, in the annotation, the report, the step
# outputs and the summary.
#
# No Ruby, datastore, container or network: the inputs are small JSON files
# written here.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
# shellcheck source=tools/testsuite/lib/assert.sh
source "${TEST_DIR}/lib/assert.sh"

AGGREGATE="${REPO_ROOT}/.github/scripts/aggregate-test-results.sh"
SUMMARIZE="${REPO_ROOT}/.github/scripts/generate-test-summary.sh"

command -v jq > /dev/null 2>&1 || {
  printf 'FAIL: jq is required (the scripts under test use it)\n' >&2
  exit 1
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/aggregate-results-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# One results file as rspec's JSON formatter writes it, reduced to what the
# aggregation reads.
results() { # <examples> <failures> <pending>
  printf '{"summary":{"example_count":%s,"failure_count":%s,"pending_count":%s,"duration":1.5},"examples":[]}\n' \
    "$1" "$2" "$3"
}

# Runs the aggregation over <dir>. Sets OUT (stdout and stderr), RC,
# OUTPUTS (what it wrote to GITHUB_OUTPUT) and REPORT (the report path).
aggregate() { # <dir>
  local outputs="${WORK}/outputs.$RANDOM"
  : > "$outputs"
  OUT="$(GITHUB_OUTPUT="$outputs" "$AGGREGATE" "$1" 2>&1)"
  RC=$?
  OUTPUTS="$(cat "$outputs")"
  REPORT="$1/unified-report.json"
}

summarize() { # <report>
  SUMMARY="$(env -u GITHUB_STEP_SUMMARY "$SUMMARIZE" "$1" 2>&1)"
}

# ── Every file readable: the totals, and nothing flagged ──────────────────
protects "a run whose results all arrived is added up and carries no warning"
DIR="${WORK}/all-readable"
mkdir -p "${DIR}/a" "${DIR}/b"
results 10 1 2 > "${DIR}/a/rspec_results_root_fast.json"
results 5 0 0 > "${DIR}/b/sqlite_migration_results.json"
aggregate "$DIR"
assert_eq "exits 0" "0" "$RC"
assert_eq "adds the examples" "15" "$(jq '.summary.total_examples' "$REPORT")"
assert_eq "counts both files" "2" "$(jq '.summary.file_count' "$REPORT")"
assert_eq "lists no unreadable file" "[]" "$(jq -c '.unreadable_files' "$REPORT")"
assert_contains "reports no unreadable file in the outputs" "unreadable_files=0" "$OUTPUTS"
assert_contains "keeps the has_results output" "has_results=true" "$OUTPUTS"
assert_not_contains "prints no warning" "::warning::" "$OUT"
summarize "$REPORT"
assert_not_contains "summary carries no warning" ":warning:" "$SUMMARY"

# ── An empty file and a truncated one beside a readable one ───────────────
protects "a results file a dead test process left behind is named, not read as an empty suite"
DIR="${WORK}/some-unreadable"
mkdir -p "${DIR}/unit" "${DIR}/simple"
results 10 0 0 > "${DIR}/unit/rspec_results_root_fast.json"
: > "${DIR}/unit/rspec_results_apps_fast.json"
printf '{"summary":{"example_count":7,' > "${DIR}/simple/rspec_results_simple.json"
aggregate "$DIR"
assert_eq "exits 0" "0" "$RC"
assert_eq "adds only what it could read" "10" "$(jq '.summary.total_examples' "$REPORT")"
assert_eq "counts only the readable file" "1" "$(jq '.summary.file_count' "$REPORT")"
assert_eq "counts the unreadable files in the report" "2" "$(jq '.summary.unreadable_file_count' "$REPORT")"
assert_eq "names them in the report" \
  "[\"${DIR}/simple/rspec_results_simple.json\",\"${DIR}/unit/rspec_results_apps_fast.json\"]" \
  "$(jq -c '.unreadable_files' "$REPORT")"
assert_contains "warns about the empty file by path" \
  "::warning::RSpec results file ${DIR}/unit/rspec_results_apps_fast.json is empty or is not JSON" "$OUT"
assert_contains "warns about the truncated file by path" \
  "::warning::RSpec results file ${DIR}/simple/rspec_results_simple.json is empty or is not JSON" "$OUT"
assert_contains "reports the count in the outputs" "unreadable_files=2" "$OUTPUTS"
assert_contains "says so in the closing notice" "2 results file(s) empty or not JSON, left out" "$OUT"
summarize "$REPORT"
assert_contains "summary warns that the totals leave files out" \
  ":warning: 2 results file(s) were empty or not JSON" "$SUMMARY"
assert_contains "summary names the empty file" "- \`${DIR}/unit/rspec_results_apps_fast.json\`" "$SUMMARY"
assert_contains "summary still shows the totals" "| Total Examples | 10 |" "$SUMMARY"

# ── Nothing readable at all ───────────────────────────────────────────────
protects "a run whose only results file is empty does not report a clean, empty aggregate"
DIR="${WORK}/none-readable"
mkdir -p "$DIR"
: > "${DIR}/rspec_results.json"
aggregate "$DIR"
assert_eq "exits 0" "0" "$RC"
assert_eq "does not claim an aggregate" "false" "$(jq '.aggregated' "$REPORT")"
assert_eq "gives the reason" "no_readable_files" "$(jq -r '.reason' "$REPORT")"
assert_eq "names the file" "[\"${DIR}/rspec_results.json\"]" "$(jq -c '.unreadable_files' "$REPORT")"
assert_contains "warns about it" "::warning::RSpec results file ${DIR}/rspec_results.json" "$OUT"
assert_contains "reports no results in the outputs" "has_results=false" "$OUTPUTS"
assert_contains "reports the count in the outputs" "unreadable_files=1" "$OUTPUTS"
summarize "$REPORT"
assert_contains "summary gives the reason" "No test results to aggregate (no_readable_files)" "$SUMMARY"
assert_contains "summary names the file" "- \`${DIR}/rspec_results.json\`" "$SUMMARY"

# ── No results files ──────────────────────────────────────────────────────
protects "a run that uploaded no results keeps its existing report"
DIR="${WORK}/no-files"
mkdir -p "$DIR"
printf '{}\n' > "${DIR}/unrelated.json"
aggregate "$DIR"
assert_eq "exits 0" "0" "$RC"
assert_eq "gives the reason" "no_files_found" "$(jq -r '.reason' "$REPORT")"
assert_contains "reports no results in the outputs" "has_results=false" "$OUTPUTS"
assert_not_contains "prints no warning" "::warning::" "$OUT"
summarize "$REPORT"
assert_not_contains "summary carries no warning" ":warning:" "$SUMMARY"

# ── A path with a space ───────────────────────────────────────────────────
protects "a results path with a space in it is one file, not two arguments"
DIR="${WORK}/with space"
mkdir -p "$DIR"
results 3 0 1 > "${DIR}/rspec_results.json"
aggregate "$DIR"
assert_eq "exits 0" "0" "$RC"
assert_eq "reads the file" "3" "$(jq '.summary.total_examples' "$REPORT")"
assert_eq "adds the pending count" "1" "$(jq '.summary.total_pending' "$REPORT")"

finish
