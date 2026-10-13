#!/usr/bin/env bash
#
# tools/testsuite/ruby4-step-outcomes-test.sh
#
# Covers .github/scripts/ruby4-step-outcomes.sh, the last step of every
# Ruby 4 preview job, and the wiring that feeds it.
#
# WHAT THIS PROTECTS
#
# Every Ruby-dependent step in the preview is continue-on-error, so a
# failed step concludes "success" everywhere but in its `outcome`. Three
# nightlies ran with bundle install and the lane failing in every job that
# ran, and the run, the jobs and the steps all reported green. The report
# step is what makes those outcomes visible; the cases below pin its
# output and check that every advisory step in the workflow reaches it.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
# shellcheck source=tools/testsuite/lib/assert.sh
source "${TEST_DIR}/lib/assert.sh"

SCRIPT="${REPO_ROOT}/.github/scripts/ruby4-step-outcomes.sh"
WORKFLOW="${REPO_ROOT}/.github/workflows/ruby-4-preview.yml"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

printf '%s\n' "$ASSERT_SUITE"

report() { # <outcomes-text>
  : > "${WORK}/summary.md"
  STEP_OUTCOMES="$1" GITHUB_STEP_SUMMARY="${WORK}/summary.md" bash "$SCRIPT" 2>&1
}

# --- a job with failures -----------------------------------------------------
printf '\nfailed steps\n'
out="$(report $'Setup Ruby test environment=success\nRun unit lane=failure\n')"
status=$?
protects "a failed advisory step is reported, and the report step itself stays green"
assert_eq "exits 0 (advisory)" "0" "$status"
assert_contains "one warning annotation per failed step" "::warning::Ruby 4: Run unit lane failed" "$out"
assert_not_contains "no warning for a passing step" "Setup Ruby test environment failed" "$out"
assert_contains "the verdict counts failures" "1 of 2 advisory steps failed under Ruby 4." "$out"
assert_contains "the failed row is marked" "| Run unit lane | ❌ failure |" "$out"
assert_contains "the passing row is marked" "| Setup Ruby test environment | ✅ success |" "$out"
protects "the run page shows the table without opening a log"
assert_contains "job summary holds the table" "| Run unit lane | ❌ failure |" "$(cat "${WORK}/summary.md")"

# --- a clean job --------------------------------------------------------------
printf '\nclean job\n'
out="$(report $'Setup Ruby test environment=success\nRun billing lane=success\nRun billing-integration lane=skipped\n')"
status=$?
assert_eq "exits 0" "0" "$status"
assert_contains "the verdict says all passed" "All 3 advisory steps passed under Ruby 4." "$out"
assert_not_contains "no warning" "::warning::" "$out"
assert_contains "a skipped step is shown as skipped" "| Run billing-integration lane | ⏭️ skipped |" "$out"

# --- refusals -----------------------------------------------------------------
printf '\nrefusals\n'
protects "a mis-wired report step fails loudly instead of printing a table that hides a step"
out="$(report $'Run unit lane\n')"
assert_eq "line without '=' exits 1" "1" "$?"
assert_contains "says why" "::error::Malformed STEP_OUTCOMES line" "$out"
out="$(report $'Run unit lane=green\n')"
assert_eq "unknown outcome exits 1" "1" "$?"
assert_contains "names the outcome" "::error::Unknown step outcome 'green'" "$out"
out="$(report $'\n\n')"
assert_eq "no steps exits 1" "1" "$?"
out="$(STEP_OUTCOMES='' bash "$SCRIPT" 2>&1)"
assert_eq "unset input exits 1" "1" "$?"

# --- every advisory step in the preview reaches the report -------------------
printf '\npreview workflow\n'
protects "an advisory step added to the preview without an id, or an id the report step does not read, fails here"
# Step blocks start at a six-space "- " line. A block with a step-level
# continue-on-error must carry an id, and that id must be read by a
# steps.<id>.outcome expression somewhere in the workflow.
advisory_ids="$(awk '
  /^      - / { if (coe && id == "") missing++; if (coe && id != "") print id; coe = 0; id = "" }
  /^        continue-on-error: true/ { coe = 1 }
  /^        id: / { id = $2 }
  END { if (coe && id == "") missing++; if (coe && id != "") print id; if (missing) print "MISSING-ID:" missing }
' "$WORKFLOW")"
assert_not_contains "every step-level continue-on-error step has an id" "MISSING-ID" "$advisory_ids"
assert_at_least "advisory steps found" 8 "$(printf '%s\n' "$advisory_ids" | grep -c .)" "advisory steps"
while IFS= read -r id; do
  [[ -z "$id" ]] && continue
  assert_contains "report reads steps.${id}.outcome" "steps.${id}.outcome" "$(cat "$WORKFLOW")"
done <<< "$advisory_ids"
jobs_with_advisory="$(awk '
  /^  [a-z-]+:$/ { job = $1 }
  /^        continue-on-error: true/ { seen[job] = 1 }
  END { n = 0; for (j in seen) n++; print n }
' "$WORKFLOW")"
reports="$(grep -c 'run: .github/scripts/ruby4-step-outcomes.sh' "$WORKFLOW")"
assert_eq "one report step per job with advisory steps" "$jobs_with_advisory" "$reports"
assert_eq "every report step runs whatever happened before it" "$reports" \
  "$(awk '
    /^      - / { if (report && always) n++; report = 0; always = 0 }
    /^        if: always\(\)/ { always = 1 }
    /run: \.github\/scripts\/ruby4-step-outcomes\.sh/ { report = 1 }
    END { if (report && always) n++; print n + 0 }
  ' "$WORKFLOW")"

finish
