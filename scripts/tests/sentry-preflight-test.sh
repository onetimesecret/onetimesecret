#!/usr/bin/env bash
#
# scripts/tests/sentry-preflight-test.sh
#
# Covers the classification ladder in scripts/ci/sentry-sourcemap-preflight.sh:
# which inputs produce status=skipped, status=blocked and status=ready, and
# which component/state pair each one records.
#
# WHAT THIS PROTECTS
#
# `sentry-cli sourcemaps upload <dir>` is happy to upload nothing, and the step
# carries continue-on-error, so an empty delivery and a complete one produce
# identical green checks. The preflight is what makes them different, and the
# distinction it draws is the load-bearing one:
#
#   skipped   nobody configured Sentry here (fork, unconfigured clone). Must
#             stay quiet, or every fork build cries wolf.
#   blocked   credentials ARE present and a precondition failed. Must be loud.
#
# Assertions are on the status value and the component/state pair, not on the
# wording of the detail: the messages are operator-facing prose that should
# stay free to improve.
#
# THE LOCAL-ENVIRONMENT TRAP
#
# A developer shell that talks to the self-hosted Sentry exports
# SENTRY_AUTH_TOKEN. The `skipped` branch below is chosen by that variable
# being EMPTY, so run naively, the no-credentials case takes the credentialed
# path and passes for the wrong reason. Every invocation here goes through
# sentry_scrub_args (`env -u ...`); nothing is inherited.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assert.sh
source "${TEST_DIR}/lib/assert.sh"

PREFLIGHT="${REPO_ROOT}/scripts/ci/sentry-sourcemap-preflight.sh"

mapfile -t SCRUB < <(sentry_scrub_args)

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sentry-preflight-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

case_no=0
CASE_DIR=""
new_case() {
  case_no=$((case_no + 1))
  CASE_DIR="${WORK}/case-${case_no}"
  mkdir -p "$CASE_DIR"
  : > "${CASE_DIR}/status.tsv"
  : > "${CASE_DIR}/output.txt"
}

preflight() { # <VAR=VALUE...>
  env "${SCRUB[@]}" \
    SENTRY_STATUS_FILE="${CASE_DIR}/status.tsv" \
    GITHUB_OUTPUT="${CASE_DIR}/output.txt" \
    "$@" \
    bash "$PREFLIGHT"
}

emitted_status() { grep -E '^status=' "${CASE_DIR}/output.txt" | tail -n1; }
rows() { cat "${CASE_DIR}/status.tsv"; }
row() { printf '%s\t%s' "$1" "$2"; }

# A dist tree that satisfies every assertion, so each case below can remove
# exactly one thing and attribute the result to that removal.
make_dist() { # <dir> <release>
  local dir="$1" release="$2"
  mkdir -p "${dir}/assets" "${dir}/.vite"
  printf 'const r="%s";export default r;\n' "$release" > "${dir}/assets/main.a1b2c3.js"
  printf '{"version":3,"sources":[]}\n' > "${dir}/assets/main.a1b2c3.js.map"
  printf 'const r="%s";export default r;\n' "$release" > "${dir}/assets/admin.d4e5f6.js"
  printf '{"version":3,"sources":[]}\n' > "${dir}/assets/admin.d4e5f6.js.map"
  printf '{}\n' > "${dir}/.vite/manifest-admin.json"
}

printf '%s\n' "$ASSERT_SUITE"

# --- no credentials ----------------------------------------------------------

printf '\nno credentials: quiet skip\n'
protects "forks and unconfigured clones hit this on every build; annotating it would train reviewers to ignore the annotations that matter"

new_case
preflight > /dev/null 2>&1
assert_eq "status=skipped" "status=skipped" "$(emitted_status)"
assert_contains "recorded as skipped, not blocked or failed" \
  "$(row sourcemaps skipped)" "$(rows)"

# An empty token is the same condition as an unset one, and it is the shape a
# fork actually gets: `secrets.SENTRY_AUTH_TOKEN` interpolates to the empty
# string rather than being absent.
new_case
preflight SENTRY_AUTH_TOKEN='' SENTRY_ORG=acme > /dev/null 2>&1
assert_eq "an empty token is the same as no token" "status=skipped" "$(emitted_status)"

# The negative control for the scrub itself. If the harness leaked an ambient
# SENTRY_AUTH_TOKEN, the two cases above would silently have taken the
# credentialed path instead — and still passed nothing but a different branch.
printf '\nthe scrub is real\n'
protects "this machine's shell exports SENTRY_AUTH_TOKEN; without env -u the no-credentials cases above test the wrong branch and prove nothing"

new_case
preflight SENTRY_AUTH_TOKEN=t0ken > /dev/null 2>&1
assert_eq "supplying a token reaches a different branch" "status=blocked" "$(emitted_status)"

# --- credentials present, preconditions missing ------------------------------

printf '\ncredentials present: each missing precondition blocks loudly\n'
protects "these are exactly the states that used to be indistinguishable from success: the upload would run, exit 0, and ship nothing"

new_case
preflight SENTRY_AUTH_TOKEN=t0ken SENTRY_RELEASE=abc1234 > /dev/null 2>&1
assert_eq "no org blocks" "status=blocked" "$(emitted_status)"
assert_contains "no org is recorded as blocked" \
  "$(row sourcemaps blocked)" "$(rows)"

new_case
preflight SENTRY_AUTH_TOKEN=t0ken SENTRY_ORG=acme > /dev/null 2>&1
assert_eq "no release blocks" "status=blocked" "$(emitted_status)"
assert_contains "an anonymous release is recorded as blocked" \
  "$(row sourcemaps blocked)" "$(rows)"

new_case
preflight SENTRY_AUTH_TOKEN=t0ken SENTRY_ORG=acme SENTRY_RELEASE=abc1234 \
  SENTRY_DIST_DIR="${CASE_DIR}/absent" > /dev/null 2>&1
assert_eq "a missing dist tree blocks" "status=blocked" "$(emitted_status)"
assert_contains "the original defect — nothing on the runner to upload — is recorded as blocked" \
  "$(row sourcemaps blocked)" "$(rows)"

new_case
mkdir -p "${CASE_DIR}/dist/assets"
printf 'console.log(1)\n' > "${CASE_DIR}/dist/assets/main.a1b2c3.js"
preflight SENTRY_AUTH_TOKEN=t0ken SENTRY_ORG=acme SENTRY_RELEASE=abc1234 \
  SENTRY_DIST_DIR="${CASE_DIR}/dist" > /dev/null 2>&1
assert_eq "a dist tree with zero .map files blocks" "status=blocked" "$(emitted_status)"
assert_contains "zero sourcemaps is recorded as blocked" \
  "$(row sourcemaps blocked)" "$(rows)"

new_case
mkdir -p "${CASE_DIR}/dist/assets"
printf 'console.log(1)\n' > "${CASE_DIR}/dist/assets/vendor.9f9f9f.js"
printf '{"version":3}\n' > "${CASE_DIR}/dist/assets/vendor.9f9f9f.js.map"
preflight SENTRY_AUTH_TOKEN=t0ken SENTRY_ORG=acme SENTRY_RELEASE=abc1234 \
  SENTRY_DIST_DIR="${CASE_DIR}/dist" > /dev/null 2>&1
assert_eq "maps present but no entry bundle blocks" "status=blocked" "$(emitted_status)"

# --- the partial delivery ----------------------------------------------------
#
# The customer bundle alone is the failure nobody notices: the site symbolicates
# and only the Colonel console's traces are raw.

printf '\npartial delivery: one bundle present, one missing\n'
protects "a half-delivered two-pass build still uploads, so it must be recorded as a warning rather than allowed through silently"

new_case
make_dist "${CASE_DIR}/dist" abc1234
rm -f "${CASE_DIR}/dist/assets/admin.d4e5f6.js.map" "${CASE_DIR}/dist/.vite/manifest-admin.json"
preflight SENTRY_AUTH_TOKEN=t0ken SENTRY_ORG=acme SENTRY_RELEASE=abc1234 \
  SENTRY_DIST_DIR="${CASE_DIR}/dist" SENTRY_PROJECTS='frontend' \
  SENTRY_PROJECT=frontend > /dev/null 2>&1
assert_eq "a missing admin bundle still uploads" "status=ready" "$(emitted_status)"
assert_contains "but it is recorded as a warning" \
  "$(row sourcemaps warn)" "$(rows)"
assert_not_contains "and not silently passed as ok" \
  "$(row sourcemaps ok)" "$(rows)"

# --- the healthy tree --------------------------------------------------------

printf '\na complete two-pass build\n'
protects "the ready path has to stay reachable: a preflight that blocks a healthy tree stops sourcemaps shipping at all, which is the defect this pipeline was built to fix"

new_case
make_dist "${CASE_DIR}/dist" abc1234
preflight SENTRY_AUTH_TOKEN=t0ken SENTRY_ORG=acme SENTRY_RELEASE=abc1234 \
  SENTRY_DIST_DIR="${CASE_DIR}/dist" SENTRY_PROJECTS='frontend backend' \
  SENTRY_PROJECT=frontend > /dev/null 2>&1
assert_eq "status=ready" "status=ready" "$(emitted_status)"
assert_not_contains "nothing about the sourcemaps is blocked" \
  "$(row sourcemaps blocked)" "$(rows)"
assert_not_contains "nothing about the sourcemaps is warned" \
  "$(row sourcemaps warn)" "$(rows)"
assert_contains "the release baked into the chunks is confirmed" \
  "$(row release-parity ok)" "$(rows)"
assert_contains "the upload's project is confirmed to be among the configured ones" \
  "$(row project-routing ok)" "$(rows)"

printf '\nrelease parity\n'
protects "bundles filed under a release no event reports are invisible; the built chunks are the only ground truth for what __SENTRY_RELEASE__ was baked with"

new_case
make_dist "${CASE_DIR}/dist" 0000000
preflight SENTRY_AUTH_TOKEN=t0ken SENTRY_ORG=acme SENTRY_RELEASE=abc1234 \
  SENTRY_DIST_DIR="${CASE_DIR}/dist" SENTRY_PROJECTS='frontend' \
  SENTRY_PROJECT=frontend > /dev/null 2>&1
assert_contains "a release absent from the built chunks warns" \
  "$(row release-parity warn)" "$(rows)"
assert_eq "the upload still proceeds — this is a warning, not a gate" \
  "status=ready" "$(emitted_status)"

printf '\nproject routing\n'
protects "if the upload's project is not one the release was created for, the release and its bundles live in different projects and neither half looks wrong alone"

new_case
make_dist "${CASE_DIR}/dist" abc1234
preflight SENTRY_AUTH_TOKEN=t0ken SENTRY_ORG=acme SENTRY_RELEASE=abc1234 \
  SENTRY_DIST_DIR="${CASE_DIR}/dist" SENTRY_PROJECTS='backend workers' \
  SENTRY_PROJECT=frontend > /dev/null 2>&1
assert_contains "an unlisted upload project warns" \
  "$(row project-routing warn)" "$(rows)"

# The detail deliberately reports a COUNT, never the slugs: SENTRY_PROJECTS is a
# repository secret and a whitespace-truncated prefix of a space-separated list
# no longer matches the registered value, so it would publish unmasked.
assert_not_contains "no project slug reaches the published detail" \
  "workers" "$(rows)"
assert_not_contains "no project slug reaches the published detail" \
  "backend" "$(rows)"

printf '\nthe preflight never gates the build\n'
protects "it runs in the image-publishing job; a non-zero exit would fail production image builds over telemetry"

new_case
preflight SENTRY_AUTH_TOKEN=t0ken SENTRY_ORG=acme SENTRY_RELEASE=abc1234 \
  SENTRY_DIST_DIR="${CASE_DIR}/absent" > /dev/null 2>&1
assert_eq "exit 0 on the blocked path" "0" "$?"

finish
