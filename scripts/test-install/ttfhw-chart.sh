#!/usr/bin/env bash
#
# scripts/test-install/ttfhw-chart.sh
#
# TTFHW trend chart (install-onboarding work-chunks, C7 residual "duration
# charted/alarmed over time"). Renders the fresh-clone job's duration across
# recent successful runs into $GITHUB_STEP_SUMMARY and emits a ::warning
# annotation when the current run regressed past the median.
#
# Metric: the Actions JOB duration (started_at -> completed_at), because that
# is the one number comparable across history via the API alone. It includes
# runner toolchain setup, so it runs a minute or two above the measured
# "documented contributor path" duration the previous step reports — the two
# numbers deliberately coexist in the summary.
#
# This script is telemetry, not a gate: every degraded path (no token, no gh,
# API error, empty history) prints why and exits 0. The workflow adds
# continue-on-error as a backstop.
#
# Env (provided by the workflow):
#   GH_TOKEN             API token with actions: read
#   GITHUB_REPOSITORY    owner/repo
#   GITHUB_RUN_ID        current run id — supplies the "this run" row from its
#                        in-progress job; skipped when absent (local runs)
#   GITHUB_STEP_SUMMARY  markdown sink (default: stdout, for local runs)
#
# Knobs:
#   TTFHW_WORKFLOW        workflow file to chart (default: fresh-clone.yml)
#   TTFHW_JOB_NAME        job display name (default: "bin/setup from zero")
#   TTFHW_HISTORY         successful runs to chart (default: 15)
#   TTFHW_REGRESSION_PCT  warn when current > median * (1 + pct/100) (default: 25)
#
# Local dry run (charts history, no "this run" row):
#   GH_TOKEN=$(gh auth token) GITHUB_REPOSITORY=onetimesecret/onetimesecret \
#     scripts/test-install/ttfhw-chart.sh

set -euo pipefail

SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
WORKFLOW="${TTFHW_WORKFLOW:-fresh-clone.yml}"
JOB_NAME="${TTFHW_JOB_NAME:-bin/setup from zero}"
HISTORY="${TTFHW_HISTORY:-15}"
PCT="${TTFHW_REGRESSION_PCT:-25}"

skip() { printf 'ttfhw-chart: %s (chart skipped)\n' "$1"; exit 0; }

command -v gh >/dev/null 2>&1 || skip "gh CLI not found"
command -v jq >/dev/null 2>&1 || skip "jq not found"
[[ -n "${GITHUB_REPOSITORY:-}" ]] || skip "GITHUB_REPOSITORY unset"
[[ -n "${GH_TOKEN:-}" ]] || skip "GH_TOKEN unset"

fmt() { printf '%dm %02ds' $(( $1 / 60 )) $(( $1 % 60 )); }

# --- history: job duration per recent successful run ---------------------------
# Name matching prefers $JOB_NAME but falls back to the run's (only) successful
# job: the job has been renamed before (install-test.sh from zero -> bin/setup
# from zero) and a rename must not blank the trend until history re-accumulates.
runs_tsv="$(gh api \
  "repos/$GITHUB_REPOSITORY/actions/workflows/$WORKFLOW/runs?status=success&per_page=$HISTORY" \
  --jq '.workflow_runs[] | [.id, .run_number, .created_at] | @tsv' 2>/dev/null)" \
  || skip "could not list $WORKFLOW runs (is 'actions: read' granted?)"

rows=""
while IFS=$'\t' read -r run_id run_number created; do
  [[ -n "$run_id" ]] || continue
  secs="$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$run_id/jobs" 2>/dev/null \
    | jq -r --arg name "$JOB_NAME" \
        '([.jobs[] | select(.conclusion == "success")] | sort_by(.name != $name))
         | first // empty
         | ((.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601))')"
  [[ -n "$secs" ]] || continue
  rows="${rows}${run_number}	${created:0:10}	${secs}
"
done <<EOF
$runs_tsv
EOF

# --- this run: its own job's started_at -> now ----------------------------------
current_secs=""
if [[ -n "${GITHUB_RUN_ID:-}" ]]; then
  started="$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/jobs" 2>/dev/null \
    | jq -r --arg name "$JOB_NAME" \
        '([.jobs[]] | sort_by(.name != $name)) | first // empty
         | (.started_at | fromdateiso8601)')"
  if [[ -n "$started" ]]; then
    current_secs=$(( $(date -u +%s) - started ))
  fi
fi

[[ -n "$rows" || -n "$current_secs" ]] || skip "no successful $WORKFLOW history yet"

# --- render: oldest -> newest, bars scaled to the slowest run -------------------
sorted="$(printf '%s' "$rows" | sort -n)"

max=0
while IFS=$'\t' read -r _ _ secs; do
  [[ -n "$secs" && "$secs" -gt "$max" ]] && max="$secs"
done <<EOF
$sorted
EOF
[[ -n "$current_secs" && "$current_secs" -gt "$max" ]] && max="$current_secs"
[[ "$max" -gt 0 ]] || skip "all durations were zero"

bar() {
  local n=$(( $1 * 30 / max )) i=0 out=""
  [[ "$n" -lt 1 ]] && n=1
  while [[ "$i" -lt "$n" ]]; do out="${out}█"; i=$(( i + 1 )); done
  printf '%s' "$out"
}

median="$(printf '%s' "$sorted" | awk -F'\t' 'NF { print $3 }' | sort -n \
  | awk '{ a[++n] = $1 }
    END { if (!n) exit
          if (n % 2) print a[(n + 1) / 2]
          else       print int((a[n / 2] + a[n / 2 + 1]) / 2) }')"

{
  echo "### TTFHW trend — \`$JOB_NAME\` job duration, last successful runs"
  echo ""
  echo "| run | date | duration | trend |"
  echo "|---|---|---|---|"
  while IFS=$'\t' read -r run_number date secs; do
    [[ -n "$secs" ]] || continue
    echo "| #$run_number | $date | $(fmt "$secs") | $(bar "$secs") |"
  done <<EOF
$sorted
EOF
  if [[ -n "$current_secs" ]]; then
    echo "| **this run** | $(date -u +%Y-%m-%d) | $(fmt "$current_secs") | $(bar "$current_secs") |"
  fi
  echo ""
  if [[ -n "$median" ]]; then
    echo "Median of history: $(fmt "$median"); regression threshold +${PCT}%."
  fi
} >> "$SUMMARY"

# --- alarm: warn (never fail) when this run regressed past the median -----------
if [[ -n "$current_secs" && -n "$median" && "$median" -gt 0 ]]; then
  threshold=$(( median * (100 + PCT) / 100 ))
  if [[ "$current_secs" -gt "$threshold" ]]; then
    delta=$(( (current_secs - median) * 100 / median ))
    echo "::warning title=TTFHW regression::$JOB_NAME took $(fmt "$current_secs"), +${delta}% vs the $(fmt "$median") median of the last runs (threshold +${PCT}%)"
    echo "" >> "$SUMMARY"
    echo "**Regression:** this run is +${delta}% vs median (threshold +${PCT}%)." >> "$SUMMARY"
  fi
fi

exit 0
