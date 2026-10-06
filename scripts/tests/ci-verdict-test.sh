#!/usr/bin/env bash
#
# scripts/tests/ci-verdict-test.sh
#
# Covers .github/scripts/ci-verdict.sh, the required `ci-verdict` check in
# ci.yml.
#
# WHAT THIS PROTECTS
#
# GitHub counts a skipped job as passing a required check. The verdict exists
# to pass a job skipped for a path the PR does not touch and to fail one
# skipped because a prerequisite failed or the run was cancelled. Each case
# below pins one side of that line, plus the two premises the line rests on:
# change detection succeeded, and [ci-skip] was not used. The last case
# checks that every test job in ci.yml has a row in the script, so a job
# added to the workflow without a verdict row fails here instead of merging
# unchecked.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assert.sh
source "${TEST_DIR}/lib/assert.sh"

SCRIPT="${REPO_ROOT}/.github/scripts/ci-verdict.sh"
WORKFLOW="${REPO_ROOT}/.github/workflows/ci.yml"

printf '%s\n' "$ASSERT_SUITE"

# Runs the script with a clean environment: EVENT_NAME=pull_request, changes
# succeeded, no [ci-skip], every flag false and every RESULT_ unset unless
# the caller sets it. Arguments are VAR=value overrides.
verdict() {
  env -i PATH="$PATH" \
    EVENT_NAME=pull_request CHANGES_RESULT=success SKIP_CI=false \
    RUBY=false TYPESCRIPT=false FRONTEND=false OCI=false AUTH=false \
    BILLING=false \
    "$@" bash "$SCRIPT" 2>&1
}

# Every job's result as one shell word list, for the all-ran cases.
ALL_SUCCESS=(
  RESULT_HOST_PROXY_WIRE=success RESULT_RUBY_LINT=success
  RESULT_TYPESCRIPT_LINT=success RESULT_HYGIENE=success
  RESULT_I18N_VALIDATE=success RESULT_BUILD_ASSETS=success
  RESULT_RUBY_UNIT=success RESULT_TYPESCRIPT_UNIT=success
  RESULT_RUBY_AUTH_BROWSER=success RESULT_RUBY_INTEGRATION_AUTH=success
  RESULT_RUBY_INTEGRATION_SIMPLE=success RESULT_RUBY_INTEGRATION_API=success
  RESULT_RUBY_INTEGRATION_FULL=success RESULT_RUBY_INTEGRATION_DISABLED=success
  RESULT_RUBY_INTEGRATION_BILLING=success RESULT_CHECK_OCI_IMAGE=success
)
ALL_SKIPPED=("${ALL_SUCCESS[@]//=success/=skipped}")

# --- everything ran and passed -----------------------------------------------
printf '\nall jobs ran and passed\n'
out="$(verdict RUBY=true TYPESCRIPT=true FRONTEND=true OCI=true AUTH=true BILLING=true "${ALL_SUCCESS[@]}")"
status=$?
protects "a fully green run is a pass"
assert_eq "exit 0" "0" "$status"
assert_contains "pass line" "✅ Every test job passed" "$out"
assert_line_count "sixteen passed rows" "16" "| success | ✅ passed |" "$out"

# --- a docs-only PR: nothing relevant changed, everything skipped ------------
printf '\ndocs-only PR, every job skipped, hygiene ran\n'
out="$(verdict "${ALL_SKIPPED[@]}" RESULT_HYGIENE=success)"
status=$?
protects "a PR that touches no tested path merges on a passing verdict"
assert_eq "exit 0" "0" "$status"
assert_contains "ruby-unit skipped for no ruby change" "| ruby-unit | skipped | ✅ no ruby change |" "$out"
assert_contains "check-oci-image skipped for no oci/frontend change" "| check-oci-image | skipped | ✅ no oci or frontend change |" "$out"

# --- ruby-only PR: typescript jobs skipped, ruby jobs ran ---------------------
printf '\nruby-only PR\n'
out="$(verdict RUBY=true "${ALL_SUCCESS[@]}" \
  RESULT_TYPESCRIPT_LINT=skipped RESULT_I18N_VALIDATE=skipped \
  RESULT_TYPESCRIPT_UNIT=skipped RESULT_CHECK_OCI_IMAGE=skipped \
  RESULT_RUBY_AUTH_BROWSER=skipped RESULT_RUBY_INTEGRATION_AUTH=skipped \
  RESULT_RUBY_INTEGRATION_BILLING=skipped)"
status=$?
protects "skipped jobs on the untouched side of the path filter are not failures"
assert_eq "exit 0" "0" "$status"
assert_contains "typescript-unit skipped ok" "| typescript-unit | skipped | ✅ no typescript change |" "$out"
assert_contains "build-assets expected via ruby" "| build-assets | success | ✅ passed |" "$out"
for job in ruby-auth-browser ruby-integration-auth; do
  assert_contains "CV-AUTH-01: ordinary Ruby skips $job" \
    "| $job | skipped | ✅ no auth change |" "$out"
done
assert_contains "CV-BILLING-01: ordinary Ruby skips the billing rows" \
  "| ruby-integration-billing | skipped | ✅ no billing change |" "$out"

# --- a T3 lane failed ---------------------------------------------------------
printf '\nan integration lane failed\n'
out="$(verdict RUBY=true "${ALL_SUCCESS[@]}" RESULT_RUBY_INTEGRATION_FULL=failure)"
status=$?
protects "one failed test job fails the verdict and is named"
assert_eq "exit 1" "1" "$status"
assert_contains "the failed row" "| ruby-integration-full | failure | ❌ did not succeed |" "$out"
assert_contains "count line" "❌ 1 job(s) did not pass" "$out"

# --- lint failed, so the ruby test jobs were skipped --------------------------
printf '\nruby-lint failed and skipped the ruby test jobs\n'
out="$(verdict RUBY=true "${ALL_SUCCESS[@]}" \
  RESULT_RUBY_LINT=failure RESULT_RUBY_UNIT=skipped \
  RESULT_RUBY_INTEGRATION_SIMPLE=skipped RESULT_RUBY_INTEGRATION_API=skipped \
  RESULT_RUBY_INTEGRATION_FULL=skipped RESULT_RUBY_INTEGRATION_DISABLED=skipped \
  RESULT_RUBY_AUTH_BROWSER=skipped RESULT_RUBY_INTEGRATION_AUTH=skipped)"
status=$?
protects "a job skipped because its prerequisite failed is a failure, not a pass: this is the case GitHub alone gets wrong"
assert_eq "exit 1" "1" "$status"
assert_contains "ruby-lint failed" "| ruby-lint | failure | ❌ did not succeed |" "$out"
assert_contains "ruby-unit skipped although ruby changed" \
  "| ruby-unit | skipped | ❌ expected to run (ruby changed) but was skipped: a prerequisite failed or the run was cancelled |" "$out"
assert_contains "six failures counted" "❌ 6 job(s) did not pass" "$out"

# --- the run was cancelled ----------------------------------------------------
printf '\nrun cancelled mid-way\n'
out="$(verdict RUBY=true TYPESCRIPT=true FRONTEND=true "${ALL_SUCCESS[@]}" \
  RESULT_RUBY_INTEGRATION_FULL=cancelled RESULT_CHECK_OCI_IMAGE=cancelled)"
status=$?
protects "a cancelled job (superseded push, manual cancel) is not a pass"
assert_eq "exit 1" "1" "$status"
assert_contains "cancelled row" "| ruby-integration-full | cancelled | ❌ did not succeed |" "$out"

# --- change detection did not succeed ----------------------------------------
printf '\nchanges job failed\n'
out="$(verdict CHANGES_RESULT=failure "${ALL_SKIPPED[@]}")"
status=$?
protects "a failed or cancelled changes job skips everything and must not read as nothing to test"
assert_eq "exit 1" "1" "$status"
assert_contains "names the premise" "Change detection did not succeed (changes: failure)" "$out"

out="$(verdict CHANGES_RESULT=cancelled "${ALL_SKIPPED[@]}")"
assert_eq "cancelled changes also exits 1" "1" "$?"

# --- [ci-skip] ----------------------------------------------------------------
printf '\n[ci-skip] in the commit message\n'
out="$(verdict SKIP_CI=true "${ALL_SKIPPED[@]}")"
status=$?
protects "a commit-message flag cannot satisfy the required check"
assert_eq "exit 1" "1" "$status"
assert_contains "names the flag" "[ci-skip] skipped every job" "$out"

# --- hygiene is gated on the event, not a path --------------------------------
printf '\nhygiene expectation follows the event\n'
out="$(verdict "${ALL_SKIPPED[@]}")"
status=$?
protects "hygiene runs on every pull_request, so a skipped hygiene on a PR is a failure"
assert_eq "exit 1 on pull_request" "1" "$status"
assert_contains "hygiene row" "| hygiene | skipped | ❌ expected to run (pull_request event changed)" "$out"

out="$(verdict EVENT_NAME=push "${ALL_SKIPPED[@]}")"
status=$?
protects "on push (the main coverage baseline) hygiene is skipped by design"
assert_eq "exit 0 on push" "0" "$status"
assert_contains "hygiene row" "| hygiene | skipped | ✅ no pull_request event change |" "$out"

# --- a result that never arrived ----------------------------------------------
printf '\nmissing result\n'
out="$(verdict RUBY=true "${ALL_SUCCESS[@]}" RESULT_RUBY_UNIT=)"
status=$?
protects "an empty needs.<job>.result (a job removed from needs, a typo in the env block) is a failure, not a pass"
assert_eq "exit 1" "1" "$status"
assert_contains "unset row" "| ruby-unit | <unset> | ❌ did not succeed |" "$out"

# --- auth expectations are independent of the Ruby flag ----------------------
printf '\nauth-specific job results\n'
for job in ruby-auth-browser ruby-integration-auth; do
  result_var="RESULT_${job^^}"
  result_var="${result_var//-/_}"
  for auth in true false; do
    for result in success failure cancelled skipped '' unknown; do
      out="$(verdict AUTH="$auth" "${ALL_SUCCESS[@]}" "$result_var=$result")"
      status=$?
      expected=1
      if [[ "$result" == success || ( "$auth" == false && "$result" == skipped ) ]]; then
        expected=0
      fi
      protects "each auth job requires success when selected, accepts an unselected skip, and never accepts a failed or missing result"
      assert_eq "CV-AUTH-02: $job auth=$auth result=[$result] exit" "$expected" "$status"
      if [[ "$result" == skipped && "$auth" == true ]]; then
        assert_contains "CV-AUTH-02: $job expected despite RUBY=false" \
          "| $job | skipped | ❌ expected to run (auth changed) but was skipped:" "$out"
      elif [[ "$expected" == 1 ]]; then
        assert_contains "CV-AUTH-02: $job bad result row" \
          "| $job | ${result:-<unset>} | ❌ did not succeed |" "$out"
      fi
    done
  done
done

out="$(verdict RUBY=true AUTH=true "${ALL_SUCCESS[@]}" \
  RESULT_RUBY_AUTH_BROWSER=skipped RESULT_RUBY_INTEGRATION_AUTH=skipped)"
status=$?
protects "both selected auth jobs skipped by a failed prerequisite count as failures"
assert_eq "CV-AUTH-03: both selected auth jobs skipped exit" 1 "$status"
assert_contains "CV-AUTH-03: both auth failures counted" '❌ 2 job(s) did not pass' "$out"

out="$(verdict RUBY=true AUTH=true "${ALL_SUCCESS[@]}" \
  RESULT_RUBY_LINT=failure RESULT_RUBY_UNIT=skipped \
  RESULT_RUBY_INTEGRATION_SIMPLE=skipped RESULT_RUBY_INTEGRATION_API=skipped \
  RESULT_RUBY_INTEGRATION_FULL=skipped RESULT_RUBY_INTEGRATION_DISABLED=skipped \
  RESULT_RUBY_AUTH_BROWSER=skipped RESULT_RUBY_INTEGRATION_AUTH=skipped)"
status=$?
assert_eq "CV-AUTH-04: selected auth with failed lint exit" 1 "$status"
assert_contains "CV-AUTH-04: forcing auth adds two failures to the existing six" \
  '❌ 8 job(s) did not pass' "$out"

# --- auth selected on its own: a label or a frontend auth path, no Ruby flag ---
printf '\nauth selected without a Ruby change\n'
AUTH_ONLY=("${ALL_SKIPPED[@]}" RESULT_HYGIENE=success RESULT_BUILD_ASSETS=success
  RESULT_RUBY_AUTH_BROWSER=success RESULT_RUBY_INTEGRATION_AUTH=success)
out="$(verdict AUTH=true "${AUTH_ONLY[@]}")"
status=$?
protects "auth selection is its own flag: it needs the build and the auth jobs, not the ordinary Ruby jobs"
assert_eq "CV-AUTH-07: auth-only run exit" 0 "$status"
assert_contains "CV-AUTH-07: ruby-unit not expected" "| ruby-unit | skipped | ✅ no ruby change |" "$out"
assert_contains "CV-AUTH-07: full-mode rows not expected" \
  "| ruby-integration-full | skipped | ✅ no ruby change |" "$out"
assert_contains "CV-AUTH-07: billing rows not expected" \
  "| ruby-integration-billing | skipped | ✅ no billing change |" "$out"

out="$(verdict AUTH=true "${AUTH_ONLY[@]}" RESULT_BUILD_ASSETS=skipped)"
status=$?
protects "the auth jobs download the frontend build, so a skipped build under auth selection is a failure"
assert_eq "CV-AUTH-08: auth-only run without a build exit" 1 "$status"
assert_contains "CV-AUTH-08: build expected for auth" \
  "| build-assets | skipped | ❌ expected to run (frontend, ruby, auth or billing changed) but was skipped:" "$out"

# --- billing expectations are independent of the Ruby and auth flags ---------
printf '\nbilling-specific job results\n'
for billing in true false; do
  for result in success failure cancelled skipped '' unknown; do
    out="$(verdict BILLING="$billing" "${ALL_SUCCESS[@]}" "RESULT_RUBY_INTEGRATION_BILLING=$result")"
    status=$?
    expected=1
    if [[ "$result" == success || ( "$billing" == false && "$result" == skipped ) ]]; then
      expected=0
    fi
    protects "the billing rows require success when selected, accept an unselected skip, and never accept a failed or missing result"
    assert_eq "CV-BILLING-02: billing=$billing result=[$result] exit" "$expected" "$status"
    if [[ "$result" == skipped && "$billing" == true ]]; then
      assert_contains "CV-BILLING-02: expected despite RUBY=false and AUTH=false" \
        "| ruby-integration-billing | skipped | ❌ expected to run (billing changed) but was skipped:" "$out"
    elif [[ "$expected" == 1 ]]; then
      assert_contains "CV-BILLING-02: bad result row" \
        "| ruby-integration-billing | ${result:-<unset>} | ❌ did not succeed |" "$out"
    fi
  done
done

BILLING_ONLY=("${ALL_SKIPPED[@]}" RESULT_HYGIENE=success RESULT_BUILD_ASSETS=success
  RESULT_RUBY_INTEGRATION_BILLING=success)
out="$(verdict BILLING=true "${BILLING_ONLY[@]}")"
status=$?
protects "billing selection is its own flag: it needs the build and the billing rows, not the auth or ordinary Ruby jobs"
assert_eq "CV-BILLING-03: billing-only run exit" 0 "$status"
assert_contains "CV-BILLING-03: auth rows not expected" \
  "| ruby-integration-auth | skipped | ✅ no auth change |" "$out"
assert_contains "CV-BILLING-03: full-mode rows not expected" \
  "| ruby-integration-full | skipped | ✅ no ruby change |" "$out"

out="$(verdict BILLING=true "${BILLING_ONLY[@]}" RESULT_BUILD_ASSETS=skipped)"
status=$?
protects "the billing rows download the frontend build, so a skipped build under billing selection is a failure"
assert_eq "CV-BILLING-04: billing-only run without a build exit" 1 "$status"
assert_contains "CV-BILLING-04: build expected for billing" \
  "| build-assets | skipped | ❌ expected to run (frontend, ruby, auth or billing changed) but was skipped:" "$out"

printf '\nmissing or malformed auth selection\n'
protects "a missing or malformed required auth output fails closed even when all jobs report success"
# The command substitution is intentionally an unexpanded invalid input.
# shellcheck disable=SC2016
for bad in '' TRUE False 1 null ' true' 'false ' $'false\n' '$(exit 0)'; do
  out="$(verdict "${ALL_SUCCESS[@]}" AUTH="$bad")"
  status=$?
  assert_eq "CV-AUTH-05: malformed auth=[$bad] exit" 1 "$status"
  assert_contains "CV-AUTH-05: malformed auth diagnostic" \
    'Auth selection is missing or malformed' "$out"
done
out="$(verdict "${ALL_SUCCESS[@]}" env -u AUTH)"
status=$?
assert_eq "CV-AUTH-06: unset auth exit" 1 "$status"
assert_contains "CV-AUTH-06: unset auth diagnostic" \
  'Auth selection is missing or malformed' "$out"

# --- every test job in ci.yml has a row ---------------------------------------
printf '\nci.yml and the script agree on the job list\n'
protects "a test job added to ci.yml without a verdict row would merge unchecked"
# Job ids are the two-space-indented keys under jobs:. The verdict itself and
# the two reporting jobs are the only ones a verdict row must not exist for.
workflow_jobs="$(awk '/^jobs:$/{f=1;next} f&&/^  [a-z0-9-]+:$/{print}' "$WORKFLOW" | tr -d ' :' \
  | grep -vxE 'changes|ci-verdict|aggregate-test-results|ci-metrics' | sort)"
script_jobs="$(grep -E '^expect [a-z0-9-]+ ' "$SCRIPT" | awk '{print $2}' | sort)"
needs_jobs="$(awk '/^  ci-verdict:$/{f=1} f&&/^    needs:$/{n=1;next} n&&/^      - /{print $2;next} n{exit}' "$WORKFLOW" \
  | grep -vx changes | sort)"
assert_at_least "job list extracted" 10 "$(printf '%s\n' "$workflow_jobs" | grep -c .)" "jobs in ci.yml"
assert_eq "script rows match ci.yml jobs" "$workflow_jobs" "$script_jobs"
assert_eq "ci-verdict needs match ci.yml jobs" "$workflow_jobs" "$needs_jobs"

protects "every row's result reaches the script: a RESULT_ env entry per needed job"
env_jobs="$(awk '/^  ci-verdict:$/{f=1;next} f&&/^  [a-z0-9-]+:$/{exit} f&&/RESULT_[A-Z0-9_]+:/{match($0,/RESULT_[A-Z0-9_]+/); print tolower(substr($0,RSTART+7,RLENGTH-7))}' "$WORKFLOW" \
  | tr '_' '-' | sort)"
assert_eq "RESULT_ env entries match ci.yml jobs" "$workflow_jobs" "$env_jobs"

finish
