#!/usr/bin/env bash
# Prints a pull request's CURRENT label names as one compact JSON array.
#
# The labels in the event payload are frozen when a run is created, so a
# re-run after someone adds ci:auth would still see the old set. Reading them
# live is what lets the label take effect on a re-run or on the next push,
# without starting a workflow run for every label event on the PR.
#
# Inputs (environment): GH_TOKEN (read by gh), GITHUB_REPOSITORY, PR_NUMBER.
# Output: json=<array> appended to GITHUB_OUTPUT when it is set, otherwise the
# array on stdout so the script can be exercised locally.
#
# A failed or unreadable lookup exits non-zero and writes nothing. It must
# never read as "this PR has no labels": the selector fails closed instead.
set -euo pipefail

fail() {
  printf '::error::%s\n' "$1" >&2
  exit 1
}

[[ $# -eq 0 ]] || fail 'Label lookup accepts environment inputs only, not command-line flags.'
[[ "${GITHUB_REPOSITORY-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
  || fail 'GITHUB_REPOSITORY must be owner/name.'
[[ "${PR_NUMBER-}" =~ ^[1-9][0-9]*$ ]] || fail 'PR_NUMBER must be a pull request number.'

# The pull request itself carries its labels, so pull-requests: read is the
# only permission this needs. Label names are untrusted text: keep them inside
# JSON, on one line, and never echo them into a workflow command.
if ! pull="$(gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}" 2>/dev/null)"; then
  fail 'Could not read the pull request from the GitHub API.'
fi
if ! labels="$(printf '%s' "$pull" | jq -ce '
  if type == "object" and (.labels | type) == "array" and all(.labels[]; (.name | type) == "string")
  then [.labels[].name]
  else error("expected a pull request with a list of labels")
  end
' 2>/dev/null)"; then
  fail 'The GitHub API response was not a pull request with a list of labels (jq is required).'
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'json=%s\n' "$labels" >> "$GITHUB_OUTPUT"
else
  printf '%s\n' "$labels"
fi
