#!/usr/bin/env bash
#
# tools/setup/new-worktree.sh — post-checkout hook (.pre-commit-config.yaml)
#
# Sets up a worktree right after `git worktree add` creates it, when this
# clone opted in:
#
#   git config ots.worktreeSetup true
#
# Worktrees whose name starts with "dev" get `bin/setup --dev`, all others
# `bin/setup --test`. Output goes to tmp/worktree-setup.log. See
# docs/development/README.md#new-worktrees-opt-in.
#
# git passes an all-zero previous ref only when `git worktree add` (or a
# clone) checks out the first commit; every other checkout exits here.
#
# Always exits 0: a failing post-checkout becomes the exit status of
# `git worktree add`, although the worktree was created.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 0

# shellcheck source=tools/setup/lib.sh
source "$ROOT/tools/setup/lib.sh"

case "${PRE_COMMIT_FROM_REF:-}" in "" | *[!0]*) exit 0 ;; esac
worktree_setup_enabled || exit 0

lane="$(worktree_setup_lane "$ROOT")"
log="$ROOT/tmp/worktree-setup.log"
mkdir -p "$ROOT/tmp"

echo "New worktree: bin/setup $lane (log: $log)"
if bin/setup "$lane" >"$log" 2>&1; then
  echo "bin/setup $lane: done"
else
  echo "bin/setup $lane: FAILED, see $log"
fi
exit 0
