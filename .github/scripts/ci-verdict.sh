#!/bin/bash
#
# One pass/fail verdict over every test job in ci.yml, for the `ci-verdict`
# job — the check to require on main.
#
# A required status check sees only one job's conclusion, and GitHub counts a
# skipped job as passing. The path-gated test jobs in ci.yml are skipped for
# two unrelated reasons: the `changes` job found nothing in their path (fine),
# or a prerequisite failed or the run was cancelled (not fine). This script
# tells them apart by re-deriving, per job, whether `changes` said it should
# run. A job that was expected to run must have succeeded; a job that was not
# expected may be skipped (or may have run and succeeded).
#
# Each row of EXPECTED mirrors that job's `if:` in ci.yml. Keep them in step:
# scripts/tests/ci-verdict-test.sh checks that every test job in ci.yml has a
# row here, but it cannot check that the gate expressions agree.
#
# Environment variables (inputs):
#   EVENT_NAME       github.event_name
#   CHANGES_RESULT   needs.changes.result
#   SKIP_CI          needs.changes.outputs.skip_ci  ([ci-skip] in the commit)
#   RUBY, TYPESCRIPT, FRONTEND, OCI, AUTH, BILLING_NIGHTLY
#                    needs.changes.outputs.<flag>; BILLING_NIGHTLY is
#                    the nightly-only selection, not a path
#   RESULT_<JOB>     needs.<job>.result, JOB upper-cased with - as _
#                    (RESULT_RUBY_UNIT, RESULT_CHECK_OCI_IMAGE, ...)
#
# Exit status: 0 when every job passes the rule above, 1 otherwise. Writes a
# table to GITHUB_STEP_SUMMARY when set.

set -u

EVENT_NAME="${EVENT_NAME:-}"
CHANGES_RESULT="${CHANGES_RESULT:-}"
SKIP_CI="${SKIP_CI:-false}"
RUBY="${RUBY:-false}"
TYPESCRIPT="${TYPESCRIPT:-false}"
FRONTEND="${FRONTEND:-false}"
OCI="${OCI:-false}"
BILLING_NIGHTLY="${BILLING_NIGHTLY:-false}"
AUTH="${AUTH:-}"
case "$AUTH" in
  true | false) ;;
  *) echo '❌ Auth selection is missing or malformed; there is no CI verdict.'; exit 1 ;;
esac

# job<TAB>expected-to-run (true|false)<TAB>why it runs
# The order is the order of the jobs in ci.yml.
EXPECTED=()
expect() { EXPECTED+=("$1	$2	$3"); }

# true when any argument is the string true.
either() {
  local flag
  for flag in "$@"; do
    [[ "$flag" == "true" ]] && { echo true; return; }
  done
  echo false
}

# true when every argument is the string true.
all_of() {
  local flag
  for flag in "$@"; do
    [[ "$flag" == "true" ]] || { echo false; return; }
  done
  echo true
}

on_pull_request=false
[[ "$EVENT_NAME" == "pull_request" ]] && on_pull_request=true

expect host-proxy-wire          "$RUBY"                     "ruby"
expect ruby-lint                "$RUBY"                     "ruby"
expect typescript-lint          "$TYPESCRIPT"               "typescript"
expect hygiene                  "$on_pull_request"          "pull_request event"
expect i18n-validate            "$TYPESCRIPT"               "typescript"
expect build-assets             "$(either "$FRONTEND" "$RUBY" "$AUTH" "$BILLING_NIGHTLY")" "frontend, ruby, auth or nightly event"
expect ruby-unit                "$RUBY"                     "ruby"
expect ruby-billing             "$BILLING_NIGHTLY"          "nightly event"
expect ruby-auth-browser        "$AUTH"                     "auth"
expect ruby-integration-auth    "$AUTH"                     "auth"
expect ruby-integration-billing "$BILLING_NIGHTLY"          "nightly event"
expect ruby-billing-integration "$BILLING_NIGHTLY"          "nightly event"
expect typescript-unit          "$TYPESCRIPT"               "typescript"
expect smoke-test               "$(all_of "$RUBY" "$TYPESCRIPT")" "ruby and typescript"
expect ruby-integration-simple  "$RUBY"                     "ruby"
expect ruby-integration-api     "$RUBY"                     "ruby"
expect ruby-integration-full    "$RUBY"                     "ruby"
expect ruby-integration-disabled "$RUBY"                    "ruby"
expect ruby-integration-strategies "$RUBY"                  "ruby"
expect check-oci-image          "$(either "$OCI" "$FRONTEND")" "oci or frontend"

rows=()
failures=0

row() { # <job> <result> <mark> <note>
  rows+=("| $1 | $2 | $3 $4 |")
}

# Change detection is the premise of every "skipped is fine" below. When it
# failed or was cancelled, every gated job is skipped and nothing was tested.
if [[ "$CHANGES_RESULT" != "success" ]]; then
  echo "❌ Change detection did not succeed (changes: ${CHANGES_RESULT:-<unset>}), so there is no CI verdict."
  echo "See the changes job. A failed or cancelled detection is not a pass."
  exit 1
fi

# [ci-skip] turns every path flag off, so every job is skipped and the rule
# below would pass. A required check that a commit message can satisfy is not
# a required check; the flag still skips the work, it just cannot merge it.
if [[ "$SKIP_CI" == "true" ]]; then
  echo "❌ [ci-skip] skipped every job; nothing was tested, so there is no CI verdict."
  echo "Push a commit without the flag (or merge with a ruleset bypass) to merge this change."
  exit 1
fi

for entry in "${EXPECTED[@]}"; do
  IFS=$'\t' read -r job expected why <<< "$entry"
  var="RESULT_${job^^}"
  var="${var//-/_}"
  result="${!var:-}"

  case "$result" in
    success)
      row "$job" "$result" "✅" "passed"
      ;;
    skipped)
      if [[ "$expected" == "true" ]]; then
        row "$job" "$result" "❌" "expected to run ($why changed) but was skipped: a prerequisite failed or the run was cancelled"
        failures=$((failures + 1))
      else
        row "$job" "$result" "✅" "no $why change"
      fi
      ;;
    *)
      row "$job" "${result:-<unset>}" "❌" "did not succeed"
      failures=$((failures + 1))
      ;;
  esac
done

{
  echo "| Job | Result | Verdict |"
  echo "|-----|--------|---------|"
  printf '%s\n' "${rows[@]}"
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"

echo
echo "Changes: ruby=$RUBY typescript=$TYPESCRIPT frontend=$FRONTEND oci=$OCI auth=$AUTH billing_nightly=$BILLING_NIGHTLY (event: ${EVENT_NAME:-<unset>})"

if [[ "$failures" -gt 0 ]]; then
  echo "❌ $failures job(s) did not pass. See the rows marked ❌ above."
  exit 1
fi

echo "✅ Every test job passed or was skipped for a path the PR does not touch."
exit 0
