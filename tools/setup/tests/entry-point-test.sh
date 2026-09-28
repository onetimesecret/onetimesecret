#!/usr/bin/env bash
#
# tools/setup/tests/entry-point-test.sh
#
# Covers bin/setup, the ADR-042 shim in front of tools/setup/setup.sh.
#
# WHAT THIS PROTECTS
#
#   - The lanes run under the interpreter that runs bin/setup. installer.yml's
#     macOS job runs `/bin/bash bin/setup` to prove the lanes work under stock
#     bash 3.2. If the shim went through setup.sh's `#!/usr/bin/env bash`
#     instead, that job would silently test whichever bash is first on PATH.
#   - Arguments reach setup.sh unchanged, and its exit status comes back
#     unchanged: bin/install, bin/doctor and CI read it.
#
# Runs the real shim against a stub setup.sh in a temp tree. The stub
# reports $BASH and its arguments. The interpreter is a symlink to bash
# under a name that is not on PATH, so only the shim passing "$BASH" can
# produce it.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../../.." && pwd)"
# shellcheck source=scripts/tests/lib/assert.sh
source "${REPO_ROOT}/scripts/tests/lib/assert.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "${WORK}/repo/bin" "${WORK}/repo/tools/setup" "${WORK}/interp"
cp "${REPO_ROOT}/bin/setup" "${WORK}/repo/bin/setup"
cat >"${WORK}/repo/tools/setup/setup.sh" <<'STUB'
#!/usr/bin/env bash
printf 'interpreter=%s\n' "$BASH"
for arg in "$@"; do printf 'arg=[%s]\n' "$arg"; done
exit "${STUB_EXIT:-0}"
STUB
chmod +x "${WORK}/repo/bin/setup" "${WORK}/repo/tools/setup/setup.sh"
INTERP="${WORK}/interp/ots-test-bash"
ln -s "$(command -v bash)" "$INTERP"

protects "the lanes run under the bash that runs bin/setup, as installer.yml's macOS job relies on"
out="$("$INTERP" "${WORK}/repo/bin/setup" --test)"
assert_contains "setup.sh runs under the invoking interpreter" "interpreter=${INTERP}" "$out"

protects "bin/setup passes arguments through untouched"
out="$("$INTERP" "${WORK}/repo/bin/setup" --doctor --operator 'two words')"
assert_contains "first argument" "arg=[--doctor]" "$out"
assert_contains "second argument" "arg=[--operator]" "$out"
assert_contains "an argument with a space stays one argument" "arg=[two words]" "$out"

protects "bin/setup returns setup.sh's exit status"
STUB_EXIT=7 "$INTERP" "${WORK}/repo/bin/setup" >/dev/null
assert_eq "exit status passes through" "7" "$?"

finish
