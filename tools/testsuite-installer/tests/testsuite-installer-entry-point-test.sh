#!/usr/bin/env bash
# Test the migration boundary in a disposable checkout, without services.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_DIR="$(cd "$TEST_DIR/.." && pwd)"
REPO_ROOT="$(cd "$TOOL_DIR/../.." && pwd)"
# shellcheck source=tools/testsuite/lib/assert.sh
source "$REPO_ROOT/tools/testsuite/lib/assert.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
REPO="$WORK/repo with spaces"
PACKAGE="$REPO/tools/testsuite-installer"
mkdir -p "$REPO/bin" "$PACKAGE" "$WORK/interp" "$WORK/stubs"
cp "$REPO_ROOT/bin/testsuite-installer" "$REPO/bin/testsuite-installer"
cp "$TOOL_DIR/testsuite-installer.sh" "$PACKAGE/testsuite-installer.sh"
INTERP="$WORK/interp/installer-bash"
ln -s "$BASH" "$INTERP"
ENTRY="$REPO/bin/testsuite-installer"

for command in run baremetal-boot secret-rotation proof-of-life check-docs-commands seed-compose-env ttfhw-chart; do
  cat > "$PACKAGE/$command.sh" <<'STUB'
#!/usr/bin/env bash
printf 'script=%s\ninterpreter=%s\ncwd=%s\n' "${0##*/}" "$BASH" "$PWD"
for arg in "$@"; do printf 'arg=[%s]\n' "$arg"; done
exit "${STUB_EXIT:-0}"
STUB
done

protects "the shim resolves its package outside the checkout, including paths with spaces"
out="$(cd "$WORK" && "$INTERP" "$ENTRY" --help)"
assert_contains "help outside checkout" "Usage: bin/testsuite-installer" "$out"

protects "every operation retains its interpreter, argument boundaries and exit status"
for command in run baremetal-boot secret-rotation proof-of-life check-docs-commands seed-compose-env ttfhw-chart; do
  out="$(cd "$WORK" && "$INTERP" "$ENTRY" "$command" 'two words' '' '--flag=value')"
  assert_contains "$command script selected" "script=$command.sh" "$out"
  assert_contains "$command interpreter preserved" "interpreter=$INTERP" "$out"
  assert_contains "$command repository cwd" "cwd=$REPO" "$out"
  assert_contains "$command arguments preserved" $'arg=[two words]\narg=[]\narg=[--flag=value]' "$out"
  STUB_EXIT=7 "$INTERP" "$ENTRY" "$command" > /dev/null
  assert_eq "$command failure passes through" "7" "$?"
done

protects "missing and misspelled commands never launch an install or overwrite .env"
out="$("$INTERP" "$ENTRY" 2>&1)"
status=$?
assert_eq "missing command exits 64" "64" "$status"
assert_not_contains "missing command dispatches nothing" "script=" "$out"
out="$("$INTERP" "$ENTRY" unknown 2>&1)"
status=$?
assert_eq "unknown command exits 64" "64" "$status"
assert_contains "unknown command message" "Unknown testsuite-installer command: unknown" "$out"

protects "container stdin receives exactly the standalone proof without executing it"
cp "$TOOL_DIR/proof-of-life.sh" "$PACKAGE/proof-of-life.sh"
(cd "$WORK" && "$INTERP" "$ENTRY" proof-of-life --print-script) > "$WORK/proof.sh"
assert_eq "script output succeeds" "0" "$?"
cmp -s "$PACKAGE/proof-of-life.sh" "$WORK/proof.sh"
assert_eq "script output is byte identical" "0" "$?"
"$INTERP" -n "$WORK/proof.sh"
assert_eq "streamed script parses" "0" "$?"
"$INTERP" "$ENTRY" proof-of-life --print-script unexpected > "$WORK/invalid-output" 2> /dev/null
assert_eq "script output rejects extra args" "64" "$?"
assert_eq "invalid script output is empty" "" "$(cat "$WORK/invalid-output")"
"$INTERP" "$ENTRY" proof-of-life > /dev/null 2>&1
assert_eq "normal proof retains missing URL failure" "64" "$?"

protects "the moved clean-room runner resolves the root without touching Docker for help or invalid lanes"
cp "$TOOL_DIR/run.sh" "$PACKAGE/run.sh"
out="$(cd "$WORK" && "$INTERP" "$ENTRY" run --help)"
assert_contains "runner help uses public command" "bin/testsuite-installer run --lane baremetal" "$out"
out="$(cd "$WORK" && "$INTERP" "$ENTRY" run --lane unknown 2>&1)"
status=$?
assert_eq "runner invalid lane exits 64" "64" "$status"
assert_contains "runner invalid lane message" "unknown lane: unknown" "$out"

protects "the relocated seed helper writes only the fixture root .env and Actions env file"
cp "$TOOL_DIR/seed-compose-env.sh" "$PACKAGE/seed-compose-env.sh"
cat > "$WORK/stubs/openssl" <<'STUB'
#!/usr/bin/env bash
printf 'test-secret\n'
STUB
cat > "$WORK/stubs/node" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$WORK/stubs/openssl" "$WORK/stubs/node"
(cd "$WORK" && PATH="$WORK/stubs:$PATH" GITHUB_ENV="$WORK/actions.env" "$INTERP" "$ENTRY" seed-compose-env)
assert_eq "seed helper succeeds" "0" "$?"
assert_eq "root env is created" $'SECRET=test-secret\nVALKEY_PASSWORD=test-secret\nRABBITMQ_USER=ots\nRABBITMQ_PASS=test-secret' "$(cat "$REPO/.env")"
assert_contains "Actions env includes auth secret" "AUTH_SECRET=test-secret" "$(cat "$WORK/actions.env")"
assert_contains "Actions env includes account ID secret" "ACCOUNT_ID_SECRET=test-secret" "$(cat "$WORK/actions.env")"
status=0
[ ! -e "$WORK/.env" ] || status=1
assert_eq "no env file in caller directory" "0" "$status"
status=0
[ ! -e "$PACKAGE/.env" ] || status=1
assert_eq "no env file in package directory" "0" "$status"

protects "the moved docs guard checks repository targets instead of the package or caller directory"
cp "$TOOL_DIR/check-docs-commands.sh" "$PACKAGE/check-docs-commands.sh"
for command in setup dev ots; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$REPO/bin/$command"
  chmod +x "$REPO/bin/$command"
done
printf 'bin/testsuite-installer check-docs-commands\n' > "$REPO/README.md"
out="$(cd "$WORK" && PATH="$WORK/stubs:$PATH" "$INTERP" "$ENTRY" check-docs-commands)"
status=$?
assert_eq "docs guard succeeds outside checkout" "0" "$status"
assert_contains "docs guard checks root README" "README.md references bin/testsuite-installer" "$out"
assert_contains "docs guard completes" "All documented commands resolve to real targets." "$out"

finish
