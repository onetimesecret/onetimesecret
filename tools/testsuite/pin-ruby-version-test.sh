#!/usr/bin/env bash
#
# tools/testsuite/pin-ruby-version-test.sh
#
# Covers .github/scripts/pin-ruby-version.sh, which ruby-4-preview.yml runs
# before every Ruby setup.
#
# WHAT THIS PROTECTS
#
# The Gemfile takes its Ruby from .ruby-version, so the preview workflow can
# only run under Ruby 4 once the checkout is pinned to it. Every step after
# the pin is continue-on-error, so a pin that silently stops working turns
# the whole workflow into green jobs that never ran a test, which is how it
# went unnoticed before. The cases below pin the script's contract against
# the real lockfile, and the last one checks that every Ruby setup step in the
# workflow has a pin step paired with it.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
# shellcheck source=tools/testsuite/lib/assert.sh
source "${TEST_DIR}/lib/assert.sh"

SCRIPT="${REPO_ROOT}/.github/scripts/pin-ruby-version.sh"
WORKFLOW="${REPO_ROOT}/.github/workflows/ruby-4-preview.yml"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

printf '%s\n' "$ASSERT_SUITE"

# A fresh copy of the repository's real pin files in $WORK/<name>.
fixture() {
  local dir="${WORK}/$1"
  mkdir -p "$dir"
  cp "${REPO_ROOT}/.ruby-version" "${REPO_ROOT}/Gemfile.lock" "$dir/"
  printf '%s\n' "$dir"
}

pin() { # <dir> <args...>
  local dir="$1"
  shift
  (cd "$dir" && bash "$SCRIPT" "$@" 2>&1)
}

# --- pins both files, and nothing else ---------------------------------------
printf '\npins the real lockfile\n'
dir="$(fixture pinned)"
out="$(pin "$dir" 9.8.7)"
status=$?
protects "Bundler loads under the pinned Ruby only when the Gemfile's source (.ruby-version) and the lockfile agree on it"
assert_eq "exits 0" "0" "$status"
assert_eq ".ruby-version holds the pinned version" "9.8.7" "$(cat "${dir}/.ruby-version")"
assert_eq "lockfile RUBY VERSION entry holds the pinned version" "  ruby 9.8.7" \
  "$(awk 'p { print; exit } $0 == "RUBY VERSION" { p = 1 }' "${dir}/Gemfile.lock")"
protects "the locked gems stay as committed, so the preview varies only the Ruby version"
assert_eq "exactly one lockfile line changes" "1" \
  "$(diff "${REPO_ROOT}/Gemfile.lock" "${dir}/Gemfile.lock" | grep -c '^>')"
protects "the run log says what the checkout was pinned to"
assert_contains "announces the pin" "::notice::Pinned the checkout to Ruby 9.8.7" "$out"

printf '\nre-pinning\n'
before="$(cat "${dir}/Gemfile.lock")"
pin "$dir" 9.8.7 > /dev/null
protects "a re-run step pins to the same result"
assert_eq "second pin is a no-op" "$before" "$(cat "${dir}/Gemfile.lock")"

# --- refuses, writing nothing ------------------------------------------------
refuses() { # <label> <dir> <args...>
  local label="$1" dir="$2"
  shift 2
  local ruby_before lock_before out status
  ruby_before="$(cat "${dir}/.ruby-version")"
  lock_before="$(cat "${dir}/Gemfile.lock")"
  out="$(pin "$dir" "$@")"
  status=$?
  assert_eq "${label}: exits non-zero" "1" "$status"
  assert_contains "${label}: says why" "::error::" "$out"
  assert_eq "${label}: .ruby-version untouched" "$ruby_before" "$(cat "${dir}/.ruby-version")"
  assert_eq "${label}: lockfile untouched" "$lock_before" "$(cat "${dir}/Gemfile.lock")"
}

printf '\nrefusals\n'
protects "a pin that cannot be applied fails its step, the one preview step that is not continue-on-error"
dir="$(fixture refusals)"
refuses "no version" "$dir"
refuses "partial version" "$dir" 4.0
refuses "shell text" "$dir" '4.0.2;true'
grep -v -x 'RUBY VERSION' "${REPO_ROOT}/Gemfile.lock" > "${dir}/Gemfile.lock"
refuses "lockfile without RUBY VERSION" "$dir" 4.0.2

# --- every Ruby setup in the preview workflow is pinned ----------------------
printf '\npreview workflow\n'
protects "a Ruby job added to the preview without the pin fails here instead of running green with no tests"
setups="$(grep -c -E 'uses: (ruby/setup-ruby@|\./\.github/actions/setup-ruby-test-env)' "$WORKFLOW")"
pins="$(grep -c -E -- '- [*&]pin-ruby-step$' "$WORKFLOW")"
assert_at_least "Ruby setup steps found" 2 "$setups" "setup steps"
assert_eq "one pin step per Ruby setup step" "$setups" "$pins"
assert_not_contains "no setup is handed a version past the pin" "ruby-version: '4" "$(cat "$WORKFLOW")"

finish
