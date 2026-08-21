#!/usr/bin/env bash
#
# scripts/tests/run.sh
#
# Runs the executable shell tests in this directory — every scripts/tests/*-test.sh.
#
# Usage:
#   scripts/tests/run.sh                  # everything
#   scripts/tests/run.sh sentry-status    # only files whose name contains this
#   UPDATE_GOLDEN=1 scripts/tests/run.sh  # rewrite the golden fixtures
#
# These are pure-text tests over scripts/ci/*.sh and the workflow files that
# call them. They need no network, no Sentry instance, no datastore and no
# container runtime, which is why they live outside tests/lanes/ — the lane
# runner exists to boot dockerized services and scrub Ruby's environment, and
# neither applies here.
#
# Each test scrubs the ambient SENTRY_* variables itself (see
# lib/assert.sh: sentry_scrub_args) because a developer shell that talks to the
# self-hosted Sentry exports SENTRY_AUTH_TOKEN, and every one of these scripts
# branches on it being empty.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# md_code() in sentry-status.sh uses printf -v and C-style for loops; the tests
# use mapfile. macOS ships bash 3.2, which has none of them, and the failure
# without this guard is a confusing syntax error inside a file the reader did
# not write. Same requirement and same remedy as tests/lanes/run.
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
  printf 'scripts/tests/run.sh needs bash 4+ (this is %s).\n' "${BASH_VERSION:-unknown}" >&2
  printf 'macOS ships 3.2: brew install bash, then re-run.\n' >&2
  exit 1
fi

filter="${1:-}"

declare -a SUITES=()
for suite in "${TEST_DIR}"/*-test.sh; do
  [ -f "$suite" ] || continue
  if [ -n "$filter" ]; then
    case "$(basename "$suite")" in
      *"$filter"*) ;;
      *) continue ;;
    esac
  fi
  SUITES+=("$suite")
done

if [ "${#SUITES[@]}" -eq 0 ]; then
  printf 'No test files matched %s in %s\n' "${filter:-*}" "$TEST_DIR" >&2
  exit 1
fi

failed=()
for suite in "${SUITES[@]}"; do
  printf '\n=== %s ===\n' "$(basename "$suite")"
  bash "$suite" || failed+=("$(basename "$suite")")
done

printf '\n===============================================\n'
if [ "${#failed[@]}" -eq 0 ]; then
  printf 'PASS: %s suite(s)\n' "${#SUITES[@]}"
  exit 0
fi

printf 'FAIL: %s of %s suite(s)\n' "${#failed[@]}" "${#SUITES[@]}"
printf '  %s\n' "${failed[@]}"
exit 1
