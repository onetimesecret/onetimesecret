#!/bin/bash
#
# Summarize the outcomes of a Ruby 4 preview job's advisory steps.
#
# The preview's Ruby-dependent steps are continue-on-error, so a step that
# fails still concludes "success" (that is what the checks API reports, and
# what `gh run view` prints). Only the step's `outcome` keeps the failure,
# and only the workflow run can read it. Each job's last step hands those
# outcomes here, and this script writes them where a reader finds them
# without opening a log: the job summary on the run page, the job log, and
# one warning annotation per failed step.
#
# Usage (from a workflow step, with `if: always()`):
#   env:
#     STEP_OUTCOMES: |
#       <label>=${{ steps.<id>.outcome }}
#       ...
#   run: .github/scripts/ruby4-step-outcomes.sh
#
# One "<label>=<outcome>" per line; <outcome> is success, failure, cancelled
# or skipped. Blank lines are ignored. Any other line is a workflow bug and
# fails this step, which is deliberately NOT continue-on-error: the report
# is the one thing that must not fail silently.
#
# Exit status: 0 whatever the outcomes say. The preview is advisory; the
# failures surface as warnings and in the summary, not as a red job.

set -euo pipefail

: "${STEP_OUTCOMES:?STEP_OUTCOMES must hold one <label>=<outcome> per line}"

total=0
failed=0
rows=''
while IFS= read -r line; do
  [[ -z "${line// /}" ]] && continue
  label="${line%%=*}"
  outcome="${line##*=}"
  if [[ "$line" != *=* || -z "$label" ]]; then
    echo "::error::Malformed STEP_OUTCOMES line (want <label>=<outcome>): ${line}" >&2
    exit 1
  fi
  case "$outcome" in
    success) mark='✅' ;;
    failure) mark='❌' ;;
    cancelled | skipped) mark='⏭️' ;;
    *)
      echo "::error::Unknown step outcome '${outcome}' for '${label}' (want success, failure, cancelled or skipped)" >&2
      exit 1
      ;;
  esac
  total=$((total + 1))
  if [[ "$outcome" == "failure" ]]; then
    failed=$((failed + 1))
    echo "::warning::Ruby 4: ${label} failed (advisory; the job stays green)"
  fi
  rows+="| ${label} | ${mark} ${outcome} |"$'\n'
done <<< "$STEP_OUTCOMES"

if [[ "$total" -eq 0 ]]; then
  echo "::error::STEP_OUTCOMES names no steps" >&2
  exit 1
fi

if [[ "$failed" -gt 0 ]]; then
  verdict="${failed} of ${total} advisory steps failed under Ruby 4."
else
  verdict="All ${total} advisory steps passed under Ruby 4."
fi

report="$(
  printf '## Ruby 4 step outcomes\n\n'
  printf '%s\n\n' "$verdict"
  printf '| Step | Outcome |\n|------|---------|\n'
  printf '%s' "$rows"
)"

printf '%s\n' "$report"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '%s\n' "$report" >> "$GITHUB_STEP_SUMMARY"
fi
