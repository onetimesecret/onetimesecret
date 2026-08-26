#!/usr/bin/env bash
#
# scripts/tests/sentry-components-drift-test.sh
#
# Asserts that the component names build-and-publish-oci-images.yml can put in
# SENTRY_EXPECTED_COMPONENTS are names something actually records.
#
# WHAT THIS PROTECTS
#
# `sentry-status.sh render <names>` synthesizes a BLOCKED row and a ::warning::
# for any name with no row. That is the assertion the anti-silent-success
# guarantee rests on, and it is held together by nothing but string equality
# between two files. A typo on either side is invisible:
#
#   * misspelled in the workflow  -> that name can never match a row, so every
#     build gets a permanent BLOCKED row and a permanent warning for a
#     component that is fine. Reviewers learn to ignore the warnings, which is
#     the cry-wolf failure this whole pipeline exists to end.
#   * renamed in a script         -> the workflow keeps asking for the old name
#     (same permanent-warning outcome) and, worse, the new name is on nobody's
#     expected list, so a step that dies before reporting under the new name is
#     back to being invisible.
#
# DIRECTION OF THE ASSERTION
#
# Every EXPECTED name must be RECORDED somewhere. Not the reverse.
#
# The reverse would be wrong, not merely stricter: release-parity,
# project-routing and dist-tag are sub-checks the preflight reports and the
# workflow deliberately never demands, because their steps are not separately
# schedulable and a missing row for them means nothing. Requiring every
# recorded name to be expected would fail the moment someone adds a legitimate
# new sub-check — a guard that fires on correct work gets deleted.
#
# The chosen direction has the property a drift guard needs: it is silent for
# legitimate additions and loud for exactly the two typos above.
#
# The EREs below are matched against workflow text containing a literal '$';
# they must not be expanded here.
# shellcheck disable=SC2016
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assert.sh
source "${TEST_DIR}/lib/assert.sh"

WORKFLOW="${REPO_ROOT}/.github/workflows/build-and-publish-oci-images.yml"
CI_SCRIPTS_DIR="${REPO_ROOT}/scripts/ci"

printf '%s\n' "$ASSERT_SUITE"

if [ ! -f "$WORKFLOW" ]; then
  printf 'FAIL: %s not found\n' "$WORKFLOW" >&2
  exit 1
fi

# Names passed to `record`, from both producers: the report()/warn() wrappers in
# scripts/ci/*.sh (each is a one-line call into sentry-status.sh) and the
# workflow's own inline `record` calls for the release, upload and deploy steps.
# Matched on shape — component then state — so a new script is picked up without
# editing this list.
recorded_components() {
  {
    grep -hoE "^[[:space:]]*(report|warn)[[:space:]]+[a-z][a-z0-9-]*[[:space:]]+(ok|skipped|warn|blocked|failed)([[:space:]]|$)" \
      "${CI_SCRIPTS_DIR}"/*.sh 2> /dev/null | awk '{ print $2 }'
    grep -hoE "sentry-status\.sh[[:space:]]+record[[:space:]]+[a-z][a-z0-9-]*[[:space:]]+(ok|skipped|warn|blocked|failed)([[:space:]]|$)" \
      "${REPO_ROOT}/.github/workflows"/*.yml 2> /dev/null | awk '{ print $3 }'
  } | sort -u
}

# The then-branch of each ternary in the SENTRY_EXPECTED_COMPONENTS block. Only
# `<cond> && 'names' || ''` contributes a name; the condition literals in the
# same expression ('pull_request', 'extracted', 'success') must not be mistaken
# for components.
expected_components() {
  awk '
    /SENTRY_EXPECTED_COMPONENTS[[:space:]]*:/ { grab = 1; next }
    grab && /\$\{\{/ { print; next }
    grab { exit }
  ' "$WORKFLOW" \
    | grep -oE "&& '[^']*' *\|\|" \
    | sed -E "s/^&& '//; s/' *\|\|\$//" \
    | tr ' ' '\n' \
    | grep -v '^$' \
    | sort -u
}

mapfile -t RECORDED < <(recorded_components)
mapfile -t EXPECTED < <(expected_components)

# --- non-vacuity -------------------------------------------------------------
#
# Both sides are recovered by pattern matching over files this test does not
# own. A refactor that changes the call shape would leave both sets empty, and
# an empty set is a subset of everything — the guard would pass forever while
# guarding nothing. The floors are deliberately below the current counts so
# ordinary additions and removals do not trip them.

printf '\nextraction is not vacuous\n'
protects "an empty extraction makes the subset assertion below trivially true, which is the failure mode of every grep-based guard"

assert_at_least "component names were recovered from the reporting scripts and workflow" \
  6 "${#RECORDED[@]}" "recorded component name(s)"
assert_at_least "component names were recovered from SENTRY_EXPECTED_COMPONENTS" \
  4 "${#EXPECTED[@]}" "expected component name(s)"

# --- the drift assertion -----------------------------------------------------

printf '\nevery expected component is one something records\n'
protects "a name on the expected list that nothing records produces a permanent BLOCKED row and a permanent warning for a component that is fine, which trains reviewers to ignore the annotations"

recorded_set=" ${RECORDED[*]} "
orphans=""
for component in "${EXPECTED[@]}"; do
  case "$recorded_set" in
    *" ${component} "*) ;;
    *) orphans="${orphans}${component} " ;;
  esac
done

assert_eq "no expected component is orphaned" "" "${orphans% }"
if [ -n "$orphans" ]; then
  printf '       expected (from %s):\n         %s\n' \
    "$(basename "$WORKFLOW")" "${EXPECTED[*]}"
  printf '       recorded (from scripts/ci/*.sh and .github/workflows/*.yml):\n         %s\n' \
    "${RECORDED[*]}"
  printf '       Either the workflow name is misspelled, or a script renamed the\n'
  printf '       component it reports under. Both leave render asserting on a\n'
  printf '       name that can never appear.\n'
fi

# --- the expansion must stay unquoted ----------------------------------------
#
# Quoting is the other way this assertion disappears without a trace. With
# quotes, "frontend-assets release sourcemaps" is ONE argument: render looks for
# a single component by that whole name, finds nothing, and prints one BLOCKED
# row for a component that does not exist — while the real components go
# unchecked. It looks like the guard is working.

printf '\nthe expected list still word-splits\n'
protects "quoting \$SENTRY_EXPECTED_COMPONENTS collapses every name into one, silently disabling the missing-row assertion while still printing a plausible-looking BLOCKED row"

render_line="$(grep -nE 'sentry-status\.sh[[:space:]]+render' "$WORKFLOW" || true)"
assert_at_least "the render invocation is still in the workflow" \
  1 "$(printf '%s' "$render_line" | grep -c . || true)" "render invocation(s)"
assert_matches "the expected list is expanded unquoted" \
  'render[[:space:]]+\$SENTRY_EXPECTED_COMPONENTS[[:space:]]*$' "$render_line"
assert_not_contains "the expansion is not quoted" \
  'render "$SENTRY_EXPECTED_COMPONENTS"' "$render_line"

# --- states are the ones render knows how to label ---------------------------
#
# render's case statement maps five states to labels and anything else to
# UNKNOWN, and its degraded recap only counts failed/blocked/warn. A sixth state
# introduced in a script would therefore render as UNKNOWN and still leave the
# recap reading clean.

printf '\nevery recorded state is one render labels and scores\n'
protects "a state render does not know renders as UNKNOWN and is skipped by the degraded recap, so the summary would read clean beside an unknown row"

mapfile -t STATES < <(
  {
    grep -hoE "^[[:space:]]*(report|warn)[[:space:]]+[a-z][a-z0-9-]*[[:space:]]+[a-z]+([[:space:]]|$)" \
      "${CI_SCRIPTS_DIR}"/*.sh 2> /dev/null | awk '{ print $3 }'
    grep -hoE "sentry-status\.sh[[:space:]]+record[[:space:]]+[a-z][a-z0-9-]*[[:space:]]+[a-z]+([[:space:]]|$)" \
      "${REPO_ROOT}/.github/workflows"/*.yml 2> /dev/null | awk '{ print $4 }'
  } | sort -u
)

assert_at_least "states were recovered" 3 "${#STATES[@]}" "state(s)"

unknown=""
for state in "${STATES[@]}"; do
  case "$state" in
    ok | skipped | warn | blocked | failed) ;;
    *) unknown="${unknown}${state} " ;;
  esac
done
assert_eq "no recorded state is outside render's vocabulary" "" "${unknown% }"

finish
