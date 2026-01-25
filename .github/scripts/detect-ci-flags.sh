#!/bin/bash
#
# Detect CI control flags from commit messages and workflow inputs.
#
# Flags detected:
#   [ci-skip] - Skip CI entirely
#   [ci-all]  - Run all jobs regardless of path filtering
#
# Usage:
#   ./detect-ci-flags.sh [--workflow-dispatch-run-all true|false]
#
# Outputs (to GITHUB_OUTPUT):
#   skip_ci=true|false
#   run_all=true|false

set -e

# Parse arguments
WORKFLOW_DISPATCH_RUN_ALL="${1:-false}"

# Get commit message
COMMIT_MSG=$(git log -1 --pretty=%B 2>/dev/null || echo "")

# Detect [ci-skip] flag
if echo "$COMMIT_MSG" | grep -q '\[ci-skip\]'; then
  SKIP_CI=true
else
  SKIP_CI=false
fi

# Detect [ci-all] flag or workflow_dispatch input
if [[ "$WORKFLOW_DISPATCH_RUN_ALL" == "true" ]]; then
  RUN_ALL=true
elif echo "$COMMIT_MSG" | grep -q '\[ci-all\]'; then
  RUN_ALL=true
else
  RUN_ALL=false
fi

# Output results
if [[ -n "$GITHUB_OUTPUT" ]]; then
  echo "skip_ci=$SKIP_CI" >> "$GITHUB_OUTPUT"
  echo "run_all=$RUN_ALL" >> "$GITHUB_OUTPUT"
else
  # Local testing - print to stdout
  echo "skip_ci=$SKIP_CI"
  echo "run_all=$RUN_ALL"
fi
