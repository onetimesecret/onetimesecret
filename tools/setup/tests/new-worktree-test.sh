#!/usr/bin/env bash
#
# tools/setup/tests/new-worktree-test.sh
#
# Covers the opt-in new-worktree setup: the post-checkout hook in
# tools/setup/new-worktree.sh and the lane choice in tools/setup/lib.sh.
#
# WHAT THIS PROTECTS
#
#   - Only a worktree that git just created is set up. The hook is installed
#     for every contributor with pre-commit, so a branch switch, or a clone
#     that has not opted in, must exit without running bin/setup.
#   - The hook never fails. git reports a failing post-checkout as a failed
#     `git worktree add`, although the worktree was created.
#   - The lane follows the worktree's name, not its path: a checkout under
#     ~/Projects/dev/ is not a dev worktree.
#
# Runs against throwaway repositories in a temp dir, with a stub bin/setup
# that records its lane. Global and system git config are ignored, so a
# developer's own ots.worktreeSetup cannot decide the result.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "${TEST_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PKG_DIR}/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assert.sh
source "${REPO_ROOT}/scripts/tests/lib/assert.sh"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
ZERO_REF=0000000000000000000000000000000000000000

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The main checkout sits under a directory named "dev", like
# ~/Projects/dev/onetimesecret, and commits the package plus a stub
# bin/setup so every worktree of it has both.
MAIN="${WORK}/dev/onetimesecret"
mkdir -p "${MAIN}/tools/setup" "${MAIN}/bin"
cp "${PKG_DIR}/lib.sh" "${PKG_DIR}/new-worktree.sh" "${MAIN}/tools/setup/"
cat >"${MAIN}/bin/setup" <<'STUB'
#!/usr/bin/env bash
echo "$1" >"$(dirname "$0")/../setup-lane"
exit "${STUB_EXIT:-0}"
STUB
chmod +x "${MAIN}/bin/setup"
git -c init.defaultBranch=main init -q "$MAIN"
git -C "$MAIN" add -A
git -C "$MAIN" -c user.name=test -c user.email=test@example.com commit -q -m init

WT_NESTED_TEST="${WORK}/dev/worktrees/feature-x/onetimesecret"
WT_NESTED_DEV="${WORK}/dev/worktrees/dev-api/onetimesecret"
WT_FLAT_DEV="${WORK}/dev/onetimesecret-worktrees/dev-flat"
for wt in "$WT_NESTED_TEST" "$WT_NESTED_DEV" "$WT_FLAT_DEV"; do
  git -C "$MAIN" worktree add -q --detach "$wt" 2>/dev/null
done

# shellcheck source=tools/setup/lib.sh
lib() { (source "${PKG_DIR}/lib.sh" && "$@"); }

# run_hook WORKTREE FROM_REF — run the hook the way pre-commit's
# post-checkout stage does. Sets rc, out and lane ("none" if bin/setup
# did not run).
run_hook() {
  rm -f "$1/setup-lane"
  out="$(cd "$1" && PRE_COMMIT_FROM_REF="$2" tools/setup/new-worktree.sh 2>&1)"
  rc=$?
  lane="$(cat "$1/setup-lane" 2>/dev/null || echo none)"
}

protects "a worktree's name, not an ancestor directory, picks its lane"
assert_eq "nested layout: name is the parent of the repo-named dir" \
  "feature-x" "$(lib worktree_name "$WT_NESTED_TEST")"
assert_eq "flat layout: name is the directory" \
  "dev-flat" "$(lib worktree_name "$WT_FLAT_DEV")"
assert_eq "an ancestor named dev does not make a dev worktree" \
  "--test" "$(lib worktree_setup_lane "$WT_NESTED_TEST")"
assert_eq "nested dev-* worktree gets the dev lane" \
  "--dev" "$(lib worktree_setup_lane "$WT_NESTED_DEV")"
assert_eq "flat dev-* worktree gets the dev lane" \
  "--dev" "$(lib worktree_setup_lane "$WT_FLAT_DEV")"

protects "clones that have not opted in are never set up"
run_hook "$WT_NESTED_TEST" "$ZERO_REF"
assert_eq "not opted in: exit status" "0" "$rc"
assert_eq "not opted in: bin/setup not run" "none" "$lane"

git -C "$MAIN" config ots.worktreeSetup true

protects "only the checkout that creates a worktree runs bin/setup"
run_hook "$WT_NESTED_TEST" "$(git -C "$MAIN" rev-parse HEAD)"
assert_eq "branch switch: exit status" "0" "$rc"
assert_eq "branch switch: bin/setup not run" "none" "$lane"

protects "an opted-in new worktree runs bin/setup in the lane its name picks"
run_hook "$WT_NESTED_TEST" "$ZERO_REF"
assert_eq "new worktree: exit status" "0" "$rc"
assert_eq "new worktree: test lane" "--test" "$lane"
assert_contains "new worktree: names the log" "tmp/worktree-setup.log" "$out"
run_hook "$WT_NESTED_DEV" "$ZERO_REF"
assert_eq "new dev worktree: dev lane" "--dev" "$lane"

protects "a failed setup never fails git worktree add"
STUB_EXIT=3 run_hook "$WT_FLAT_DEV" "$ZERO_REF"
assert_eq "failed setup: exit status" "0" "$rc"
assert_contains "failed setup: says so" "FAILED" "$out"

finish
