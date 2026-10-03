#!/usr/bin/env bash
#
# scripts/tests/ci-metrics-breakdown-test.sh
#
# Covers scripts/ci/ci-metrics-breakdown.sh, the test-step half of the T5 CI
# Metrics report.
#
# WHAT THIS PROTECTS
#
# The report exists to make three things visible that the tier table hides:
# a tier that "completed" with a failed or skipped job, a test step that got
# slower than main, and a change in which test steps ran at all. Each case
# below pins one of those against a hand-written jobs listing, so a jq edit
# that quietly drops a row, counts a failed step into the baseline, or flags
# every 2-second jitter is caught here rather than read off a PR comment
# weeks later.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assert.sh
source "${TEST_DIR}/lib/assert.sh"

SCRIPT="${REPO_ROOT}/scripts/ci/ci-metrics-breakdown.sh"
FIXTURES="${TEST_DIR}/fixtures/ci-metrics"
CURRENT="${FIXTURES}/current.json"
BASELINE_A="${FIXTURES}/baseline-a.json"
BASELINE_B="${FIXTURES}/baseline-b.json"

printf '%s\n' "$ASSERT_SUITE"

# --- with a two-run baseline -------------------------------------------------
#
# current.json: Ruby Unit passed (queued 40s, ran 300s; browser lane 20s, unit
# lane 200s), TypeScript Unit FAILED, Simple Mode SKIPPED, a Full/MFA job that
# neither baseline has (queued 30s), Container Validation queued 50s.
# baseline-a/b: every job queued 5s; Ruby Unit ran 240s in both; unit lane
# 150s and 160s (median 155), browser lane 18s and 22s (median 20), Simple
# lane 120s in both, and baseline-b's TypeScript step failed — so it must not
# count toward that step's median.

printf '\nwith baseline\n'
out="$(bash "$SCRIPT" "$CURRENT" "$BASELINE_A" "$BASELINE_B")"
status=$?
assert_eq "exit status is 0: the report is information, not a gate" "0" "$status"

protects "a tier whose jobs all passed reads as success, with the count"
assert_contains "T1 success" "| T1 | ✅ success | 1 succeeded |" "$out"
assert_contains "T4 success" "| T4 | ✅ success | 1 succeeded |" "$out"

protects "a tier with a failed job must not read as complete; the failed job is named"
assert_contains "T2 partial, naming the failure" "| T2 | ⚠️ partial | 1 succeeded, failure: TypeScript Unit Tests |" "$out"

protects "a skipped job is reported as skipped, not silently absent from the tier"
assert_contains "T3 partial with a skip" "| T3 | ⚠️ partial | 1 succeeded, 1 skipped |" "$out"

protects "a job's queue wait and runtime are reported separately, and a runtime 25%/15s over the main median is flagged"
assert_contains "Ruby Unit job: queued 40s, ran 300s against 240s, flagged" \
  "| Ruby Unit Tests | success | 40s | 5m 0s | 4m 0s | +25% | ⚠️ slower |" "$out"
assert_contains "Container job: at baseline, unflagged" \
  "| Container Validation | success | 50s | 3m 0s | 3m 0s | 0% |  |" "$out"

protects "a failed or skipped job is marked as such on its own row"
assert_contains "TypeScript job failed: runtime shown, no delta" "| TypeScript Unit Tests | failure | 10s | 2m 0s | 2m 0s |  | ❌ |" "$out"
assert_contains "Simple job skipped" "| Ruby Integration (Simple Mode) | skipped | — | — | 3m 0s |  | ⏭️ skipped |" "$out"

protects "a job with no baseline is marked new"
assert_contains "MFA job new" "| Ruby Integration (Full, SQLite, MFA) | success | 30s | 1m 0s | — |  | 🆕 new |" "$out"

protects "queue wait is summarized — when the test jobs were released and the longest wait — and never flagged"
assert_contains "queue line" \
  "Queue: the T2/T3 jobs were released 20s after the workflow started (T0/T1 done) and waited up to 40s for a runner (longest: Ruby Unit Tests; median wait on main 5s)." "$out"
assert_contains "queue disclaimer" "Queue time is runner availability, not the change under test, and is never flagged." "$out"

protects "a step that is both 25% and 15s slower than the main median is flagged"
assert_contains "unit lane flagged: 200s against a median of 155s" \
  "| Ruby Unit Tests · unit lane | 3m 20s | 2m 35s | +29% | ⚠️ slower |" "$out"

protects "a step at its baseline is reported without a flag"
assert_contains "browser lane unflagged: 20s against a median of 20s" \
  "| Ruby Unit Tests · browser lane | 20s | 20s | 0% |  |" "$out"

protects "a failed step shows its conclusion instead of a duration, and a failed baseline step never enters the median"
assert_contains "TypeScript step failed; baseline is the one successful run (100s)" \
  "| TypeScript Unit Tests · TypeScript tests with coverage | failure | 1m 40s |  | ❌ |" "$out"

protects "a step with no baseline is marked new rather than compared to nothing"
assert_contains "Full/MFA row is new" \
  "| Ruby Integration (Full, SQLite, MFA) · lane | 30s | — |  | 🆕 new |" "$out"

protects "a step the baseline ran but this run did not is listed, so lost coverage is visible"
assert_contains "Simple lane not in this run" \
  "| Ruby Integration (Simple Mode) · simple lane | not run | 2m 0s |  | ⏭️ not in this run |" "$out"

protects "setup and diagnostic steps are not test execution and stay out of the table"
assert_not_contains "no diagnostic probe row" "diagnostic probe" "$out"
assert_not_contains "no Playwright install row" "Playwright" "$out"
assert_not_contains "no T1 step row" "rubocop" "$out"

protects "the baseline is identified: how many runs, which ones, so a reader can check it"
assert_contains "baseline count" "median of 2 successful \`main\` run(s)" "$out"
assert_contains "baseline run link a" "[801](https://github.com/o/r/actions/runs/801) \`aaaaaaaa\`" "$out"
assert_contains "baseline run link b" "[802](https://github.com/o/r/actions/runs/802) \`bbbbbbbb\`" "$out"

protects "the footer says what the numbers are and what the flag means"
assert_contains "time definitions" "Job time is the job's own start to finish (setup, tests, uploads); step time is the step's own start to finish" "$out"
assert_contains "flag definition" "at least 25% and 15s slower" "$out"

# --- flag guard --------------------------------------------------------------

printf '\nabsolute-seconds guard\n'
protects "a small step's percentage jump alone must not flag; the seconds floor is honored"
out="$(CI_METRICS_FLAG_MIN=60 bash "$SCRIPT" "$CURRENT" "$BASELINE_A" "$BASELINE_B")"
assert_contains "unit lane +45s is under a 60s floor: reported, not flagged" \
  "| Ruby Unit Tests · unit lane | 3m 20s | 2m 35s | +29% |  |" "$out"
assert_contains "Ruby Unit job +60s is not under a 60s floor: still flagged" \
  "| Ruby Unit Tests | success | 40s | 5m 0s | 4m 0s | +25% | ⚠️ slower |" "$out"
assert_contains "footer reflects the configured floor" "at least 25% and 60s slower" "$out"

# --- without a baseline ------------------------------------------------------

printf '\nwithout baseline\n'
protects "with no main run to compare against, the report says so instead of inventing a baseline"
out="$(bash "$SCRIPT" "$CURRENT")"
status=$?
assert_eq "exit status is 0 without a baseline" "0" "$status"
assert_contains "no-baseline note" "_No baseline: no successful \`main\` run" "$out"
assert_contains "steps still listed, unflagged" "| Ruby Unit Tests · unit lane | 3m 20s | — |  |  |" "$out"
assert_contains "jobs still listed with queue and runtime, unflagged" "| Ruby Unit Tests | success | 40s | 5m 0s | — |  |  |" "$out"
assert_contains "queue line without a main median" "waited up to 40s for a runner (longest: Ruby Unit Tests)." "$out"
assert_not_contains "nothing flagged" "⚠️ slower" "$out"
assert_not_contains "nothing marked new when there is no baseline to be new against" "🆕 new" "$out"
assert_not_contains "no not-in-this-run rows" "not in this run" "$out"

# --- usage -------------------------------------------------------------------

printf '\nusage\n'
protects "a call with no listing is a caller bug, exit 64, not an empty report"
bash "$SCRIPT" > /dev/null 2>&1
assert_eq "exit 64 without arguments" "64" "$?"

finish
