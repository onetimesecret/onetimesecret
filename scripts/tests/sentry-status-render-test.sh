#!/usr/bin/env bash
#
# scripts/tests/sentry-status-render-test.sh
#
# Covers `scripts/ci/sentry-status.sh render [expected-component ...]`.
#
# WHAT THIS PROTECTS
#
# Every Sentry step in build-and-publish-oci-images.yml carries
# `continue-on-error: true`, so the step's exit code says nothing and the job
# is green either way. `render` is the replacement signal, and the PR's whole
# thesis is that SILENT SUCCESS IS THE BUG: a step that failed, was skipped, or
# was killed before it could report must never leave the job summary reading
# clean. Each assertion below pins one way that guarantee can be lost.
#
# The interesting failures are not "render crashed" — they are "render printed
# something reassuring". So the assertions are mostly about what must NOT be in
# the output.
#
# Literal '$' inside single quotes is the subject matter: the `bash -c` bodies
# below must reach bash unexpanded so bash, not this shell, performs the word
# splitting under test.
# shellcheck disable=SC2016
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assert.sh
source "${TEST_DIR}/lib/assert.sh"

STATUS_SCRIPT="${REPO_ROOT}/scripts/ci/sentry-status.sh"
GOLDEN_DIR="${TEST_DIR}/fixtures/sentry-status"

mapfile -t SCRUB < <(sentry_scrub_args)

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sentry-render-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

case_no=0
new_case() { # -> echoes a fresh case directory
  case_no=$((case_no + 1))
  local dir="${WORK}/case-${case_no}"
  mkdir -p "$dir"
  : > "${dir}/status.tsv"
  : > "${dir}/summary.md"
  printf '%s' "$dir"
}

# Runs the script the way a workflow step does: fixed status file, fixed
# summary file, no inherited Sentry configuration.
status() { # <case-dir> <args...>
  local dir="$1"
  shift
  env "${SCRUB[@]}" \
    SENTRY_STATUS_FILE="${dir}/status.tsv" \
    GITHUB_STEP_SUMMARY="${dir}/summary.md" \
    bash "$STATUS_SCRIPT" "$@"
}

# The workflow interpolates SENTRY_EXPECTED_COMPONENTS UNQUOTED so each name
# arrives as its own argument. That behaviour belongs to the SHELL, and this
# machine's interactive shell is zsh, which does not word-split an unquoted
# expansion: a test written for the ambient shell would pass whether or not the
# workflow's contract holds. `bash -c` is therefore not a stylistic choice, it
# is the thing under test.
render_unquoted() { # <case-dir> <SENTRY_EXPECTED_COMPONENTS value>
  local dir="$1" expected="$2"
  env "${SCRUB[@]}" \
    SENTRY_STATUS_FILE="${dir}/status.tsv" \
    GITHUB_STEP_SUMMARY="${dir}/summary.md" \
    SENTRY_EXPECTED_COMPONENTS="$expected" \
    bash -c 'bash "$1" render $SENTRY_EXPECTED_COMPONENTS' _ "$STATUS_SCRIPT"
}

summary_of() { cat "${1}/summary.md"; }

printf '%s\n' "$ASSERT_SUITE"

# --- the pull_request path ---------------------------------------------------
#
# On pull_request every one of the four ternaries in SENTRY_EXPECTED_COMPONENTS
# yields '', and the folded YAML scalar collapses to whitespace. Unquoted, that
# is ZERO arguments — so this case must reproduce the folded-whitespace value
# rather than calling `render` with a clean empty string.

printf '\npull_request: nothing expected, nothing ran\n'
protects "the pull_request path is the one case where an empty summary is correct; it must keep reading as by-design, not as a failure"

dir="$(new_case)"
out="$(render_unquoted "$dir" '   ')"
summary="$(summary_of "$dir")"

assert_golden "whitespace-only expected list renders the unchanged by-design message" \
  "${GOLDEN_DIR}/pull-request-no-steps.md" "$summary"
assert_not_contains "no result table when nothing was expected" \
  "| Component | Result |" "$summary"
assert_not_contains "no annotation for a by-design empty run" "::warning::" "$out"

# --- an empty status file WITH expectations ----------------------------------
#
# This is the case the assertion exists for. A step killed by a runner OOM, a
# cancellation or a step timeout leaves continue-on-error holding an empty
# output, every downstream `if:` false, and no row at all. Before the expected
# list, that was byte-identical to a clean pull_request run.

printf '\nkilled chain: expectations recorded no rows at all\n'
protects "a delivery chain that never started must not render the reassuring 'no steps ran' message"

dir="$(new_case)"
out="$(render_unquoted "$dir" 'frontend-assets release')"
summary="$(summary_of "$dir")"

assert_golden "empty status file plus expectations renders all-BLOCKED" \
  "${GOLDEN_DIR}/expected-but-nothing-reported.md" "$summary"
assert_not_contains "the by-design message is suppressed once something was expected" \
  "No Sentry delivery steps ran" "$summary"
assert_contains "frontend-assets is BLOCKED" "| frontend-assets | **BLOCKED** |" "$summary"
assert_contains "release is BLOCKED" "| release | **BLOCKED** |" "$summary"
assert_contains "each missing component gets its own annotation" \
  "::warning::Sentry frontend-assets did NOT ship" "$out"
assert_contains "each missing component gets its own annotation" \
  "::warning::Sentry release did NOT ship" "$out"
assert_contains "the recap names both" \
  "delivery is degraded for: frontend-assets,release." "$summary"

# --- word splitting is the contract ------------------------------------------

printf '\nword splitting: the expected list is many arguments, not one\n'
protects "quoting \$SENTRY_EXPECTED_COMPONENTS in the workflow would collapse every name into one bogus component and silently disable the whole assertion"

argc="$(env "${SCRUB[@]}" \
  SENTRY_EXPECTED_COMPONENTS='frontend-assets release sourcemaps' \
  bash -c 'set -- $SENTRY_EXPECTED_COMPONENTS; echo $#')"
assert_eq "an unquoted three-name expansion is three arguments under bash" "3" "$argc"

dir="$(new_case)"
render_unquoted "$dir" 'frontend-assets release' > /dev/null
summary="$(summary_of "$dir")"
assert_line_count "two names produce two rows" 2 "**BLOCKED**" "$summary"
assert_not_contains "the names are never treated as a single component" \
  "| frontend-assets release |" "$summary"

# The folded scalar emits runs of spaces and leading/trailing whitespace when
# some of the four ternaries are false. Those empty fields must not become
# components: an empty-named BLOCKED row is unactionable noise.
printf '\nfolded YAML shape: empty ternaries leave whitespace runs\n'
protects "three of the four expected components are conditional, so the real value routinely carries empty fields"

dir="$(new_case)"
out="$(render_unquoted "$dir" '  frontend-assets release   sourcemaps  ')"
summary="$(summary_of "$dir")"
assert_line_count "exactly three rows, no empties" 3 "**BLOCKED**" "$summary"
assert_line_count "no row with an empty component name" 0 "|  | **BLOCKED**" "$summary"
assert_line_count "one annotation per real name" 3 "did NOT ship" "$out"

# --- present components ------------------------------------------------------

printf '\npresent components are rendered from their rows\n'
protects "a component that did report must be shown with the state it reported, never re-synthesized"

dir="$(new_case)"
status "$dir" record frontend-assets ok "extracted 12 .js, 12 .map" > /dev/null
status "$dir" record release skipped "SENTRY_AUTH_TOKEN not configured" > /dev/null
out="$(render_unquoted "$dir" 'frontend-assets release')"
summary="$(summary_of "$dir")"

assert_contains "an ok row renders OK" "| frontend-assets | **OK** |" "$summary"
assert_contains "a skipped row renders SKIPPED" "| release | **SKIPPED** |" "$summary"
assert_line_count "nothing is synthesized when every expectation reported" \
  0 "**BLOCKED**" "$summary"
assert_not_contains "no did-NOT-ship annotation when every expectation reported" \
  "did NOT ship" "$out"

printf '\nrecap: the clean branch\n'
protects "ok and skipped are the only two states that may leave the recap clean; anything else must degrade it"

assert_contains "clean recap" \
  "> All Sentry delivery checks passed or were cleanly skipped." "$summary"
assert_not_contains "clean recap does not also claim degradation" \
  "delivery is degraded" "$summary"
assert_not_contains "a clean run emits no degraded annotation" \
  "::warning::Sentry delivery degraded" "$out"

# --- one present, one missing ------------------------------------------------

printf '\nmixed: one reported, one vanished\n'
protects "a partially-reported chain must name exactly the component that vanished, not all of them and not none"

dir="$(new_case)"
status "$dir" record release ok "release abc1234 created" > /dev/null
out="$(render_unquoted "$dir" 'release sourcemaps-verify')"
summary="$(summary_of "$dir")"

assert_contains "the reported component keeps its own state" "| release | **OK** |" "$summary"
assert_contains "the vanished component is BLOCKED" \
  "| sourcemaps-verify | **BLOCKED** |" "$summary"
assert_contains "the BLOCKED detail says why the state is unknown" \
  "the step never reported a result" "$summary"
assert_line_count "only the vanished one is synthesized" 1 "**BLOCKED**" "$summary"
assert_contains "recap names only the vanished component" \
  "delivery is degraded for: sourcemaps-verify." "$summary"
assert_not_contains "a healthy component is never listed as degraded" \
  "degraded for: release" "$summary"
assert_contains "the degraded run gets its own annotation" \
  "::warning::Sentry delivery degraded for: sourcemaps-verify" "$out"

# --- recap aggregation -------------------------------------------------------

printf '\nrecap: every non-clean state degrades, once each\n'
protects "warn, blocked and failed each mean something did not ship; a recap that lists a component twice or drops one is the same silent-success failure in miniature"

dir="$(new_case)"
status "$dir" record frontend-assets ok "fine" > /dev/null
status "$dir" record sourcemaps warn "customer bundle sourcemap missing" > /dev/null
status "$dir" record sourcemaps warn "admin bundle missing" > /dev/null
status "$dir" record release blocked "SENTRY_PROJECTS is empty" > /dev/null
status "$dir" record deploy failed "deploy notification exited 3" > /dev/null
out="$(render_unquoted "$dir" 'frontend-assets sourcemaps release deploy sourcemaps-verify')"
summary="$(summary_of "$dir")"

assert_contains "warn, blocked, failed and missing all degrade, deduplicated and in file order" \
  "delivery is degraded for: sourcemaps,release,deploy,sourcemaps-verify." "$summary"
assert_line_count "a component reporting twice is listed once" \
  1 "delivery is degraded for:" "$summary"
assert_contains "warn renders as WARNING" "| sourcemaps | **WARNING** |" "$summary"
assert_contains "blocked renders as BLOCKED" "| release | **BLOCKED** |" "$summary"
assert_contains "failed renders as FAILED" "| deploy | **FAILED** |" "$summary"
assert_contains "the ok row survives alongside them" "| frontend-assets | **OK** |" "$summary"
assert_contains "the summary states that the image build is unaffected" \
  "The image build is unaffected" "$summary"
assert_contains "degraded annotation points at the job summary" \
  "(see the run's job summary)" "$out"

# --- a state render does not recognise ---------------------------------------
#
# `record` normalises any unrecognised state to `warn` before writing, so this
# row cannot be produced through it. It is written straight to the status file
# to reach the branch a sixth state would open: the table renders UNKNOWN, and
# the recap has to score that as degraded rather than leaving the summary
# claiming everything passed directly beneath it.
#
# Nagios settled this shape decades ago — UNKNOWN is a fourth state and it is
# not OK. The recap is written as "not ok and not skipped" for exactly that
# reason; scored against a list of bad states, a new state defaults to clean.

printf '\nunrecognised state: UNKNOWN must degrade, not pass\n'
protects "a state render has no case for must never leave the recap reading clean; scoring against a blocklist means the next state added to record silently passes"

dir="$(new_case)"
status "$dir" record frontend-assets ok "extracted 12 .js, 12 .map" > /dev/null
printf 'sourcemaps\tdegraded\tupload reported a partial bundle\n' >> "${dir}/status.tsv"
out="$(render_unquoted "$dir" 'frontend-assets sourcemaps')"
summary="$(summary_of "$dir")"

assert_contains "an unrecognised state renders as UNKNOWN" \
  "| sourcemaps | **UNKNOWN** |" "$summary"
assert_contains "the unrecognised row degrades the recap" \
  "delivery is degraded for: sourcemaps." "$summary"
assert_not_contains "the clean recap must not appear beneath an UNKNOWN row" \
  "All Sentry delivery checks passed" "$summary"
assert_contains "the unrecognised row gets a degraded annotation" \
  "::warning::Sentry delivery degraded for: sourcemaps" "$out"
assert_not_contains "an unrecognised state is not silently treated as ok" \
  "| sourcemaps | **OK** |" "$summary"

# The negative control for the assertion above: `ok` and `skipped` are named
# exemptions, not the result of failing to match a blocklist. Without this, an
# awk that scored every row as degraded would pass every assertion above.
dir="$(new_case)"
status "$dir" record release skipped "SENTRY_AUTH_TOKEN not configured" > /dev/null
out="$(render_unquoted "$dir" 'release')"
summary="$(summary_of "$dir")"

assert_contains "skipped still leaves the recap clean" \
  "> All Sentry delivery checks passed or were cleanly skipped." "$summary"
assert_not_contains "skipped is not swept up as degraded" \
  "delivery is degraded" "$summary"

# --- rows with no expectations ----------------------------------------------
#
# The preflight reports release-parity, project-routing and dist-tag, none of
# which the workflow ever names as expected. They must still render.

printf '\nzero expectations, non-empty status file\n'
protects "sub-checks report rows without being on the expected list; render with no arguments must still show them"

dir="$(new_case)"
status "$dir" record dist-tag ok "neither the upload nor the frontend sets a dist" > /dev/null
status "$dir" record release-parity warn "release not found in built chunks" > /dev/null
out="$(status "$dir" render)"
summary="$(summary_of "$dir")"

assert_contains "unexpected components still render" "| dist-tag | **OK** |" "$summary"
assert_contains "unexpected components still render" "| release-parity | **WARNING** |" "$summary"
assert_not_contains "a populated status file never reads as 'nothing ran'" \
  "No Sentry delivery steps ran" "$summary"
assert_contains "a warn row degrades the recap even with no expectations" \
  "delivery is degraded for: release-parity." "$summary"
assert_line_count "no rows are synthesized when nothing was expected" \
  0 "**BLOCKED**" "$summary"

# --- render never gates ------------------------------------------------------

printf '\nrender is a reporter, never a gate\n'
protects "render runs in a step the build depends on; a non-zero exit from the reporter would fail image builds over telemetry"

dir="$(new_case)"
render_unquoted "$dir" 'frontend-assets release' > /dev/null
assert_eq "exit 0 even when everything is BLOCKED" "0" "$?"

dir="$(new_case)"
rm -f "${dir}/status.tsv"
out="$(render_unquoted "$dir" 'frontend-assets')"
rc=$?
assert_eq "exit 0 when the status file does not exist at all" "0" "$rc"
assert_contains "a missing status file is treated as a missing row, not an error" \
  "::warning::Sentry frontend-assets did NOT ship" "$out"

finish
