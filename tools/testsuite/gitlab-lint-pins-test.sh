#!/usr/bin/env bash
#
# tools/testsuite/gitlab-lint-pins-test.sh
#
# Asserts that the tool versions pinned in more than one file agree.
#
# WHAT THIS PROTECTS
#
# .github/workflows/static-analysis.yml and .gitlab/ci/lint.yml run the same
# checks on two hosts. scripts/install-shell-lint-tools.sh reads the shellcheck
# and actionlint pins from the workflow, so those cannot drift between hosts.
# Three pins are copies:
#
#   * BUNDLER_AUDIT_VERSION in lint.yml, copied from the workflow's env block;
#   * UV_VERSION in lint.yml, copied from the workflow's `uv==` install step;
#   * SHELLCHECK_VERSION and ACTIONLINT_VERSION in check-shell-lint.sh, which
#     name the versions its baselines were recorded under.
#
# A bump on one side only would make the two hosts run different tool
# versions, or make check-shell-lint.sh compare findings against a baseline
# from another version, and neither shows up as a failure anywhere else.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
# shellcheck source=tools/testsuite/lib/assert.sh
source "${TEST_DIR}/lib/assert.sh"

WORKFLOW="${REPO_ROOT}/.github/workflows/static-analysis.yml"
GITLAB_LINT="${REPO_ROOT}/.gitlab/ci/lint.yml"
SHELL_LINT="${REPO_ROOT}/scripts/check-shell-lint.sh"

printf '%s\n' "$ASSERT_SUITE"

for file in "$WORKFLOW" "$GITLAB_LINT" "$SHELL_LINT"; do
  if [ ! -f "$file" ]; then
    printf 'FAIL: %s not found\n' "$file" >&2
    exit 1
  fi
done

# Prints the single value a sed -nE expression extracts from a file, or
# nothing when it matches no line or more than one.
only() { # <sed-expression> <file>
  local values
  values="$(sed -nE "$1" "$2")"
  [ "$(printf '%s' "$values" | grep -c '')" -eq 1 ] && printf '%s' "$values"
}

workflow_env() { only "s/^  $1: '([^']+)'\$/\\1/p" "$WORKFLOW"; }
lint_variable() { only "s/^    $1: '([^']+)'\$/\\1/p" "$GITLAB_LINT"; }
shell_lint_pin() { only "s/^$1=\"([^\"]+)\"\$/\\1/p" "$SHELL_LINT"; }

protects "GitLab and GitHub audit Gemfile.lock with the same bundler-audit"
expected="$(workflow_env BUNDLER_AUDIT_VERSION)"
assert_matches "static-analysis.yml pins one bundler-audit version" '^[0-9]+\.[0-9]+\.[0-9]+$' "$expected"
assert_eq "lint.yml BUNDLER_AUDIT_VERSION matches static-analysis.yml" \
  "$expected" "$(lint_variable BUNDLER_AUDIT_VERSION)"

protects "GitLab and GitHub run the logship tests under the same uv"
expected="$(only "s/.*'uv==([0-9.]+)'.*/\\1/p" "$WORKFLOW")"
assert_matches "static-analysis.yml installs one uv version" '^[0-9]+\.[0-9]+\.[0-9]+$' "$expected"
assert_eq "lint.yml UV_VERSION matches static-analysis.yml" \
  "$expected" "$(lint_variable UV_VERSION)"

protects "check-shell-lint.sh names the versions its baselines were recorded under"
for tool in SHELLCHECK ACTIONLINT; do
  expected="$(workflow_env "${tool}_VERSION")"
  assert_matches "static-analysis.yml pins one ${tool}_VERSION" '^[0-9]+\.[0-9]+\.[0-9]+$' "$expected"
  assert_eq "check-shell-lint.sh ${tool}_VERSION matches static-analysis.yml" \
    "$expected" "$(shell_lint_pin "${tool}_VERSION")"
done

finish
