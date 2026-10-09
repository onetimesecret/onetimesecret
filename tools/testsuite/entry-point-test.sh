#!/usr/bin/env bash
# Exercise the public shim and package dispatch against stubs, without services.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
# shellcheck source=tools/testsuite/lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/repo/bin" "$WORK/repo/tools/testsuite" "$WORK/stubs" "$WORK/interp"
cp "$REPO_ROOT/bin/testsuite" "$WORK/repo/bin/testsuite"
cp "$TEST_DIR/testsuite.sh" "$WORK/repo/tools/testsuite/testsuite.sh"
for script in run.sh verify-sentry-build.sh; do
  cat > "$WORK/repo/tools/testsuite/$script" <<'STUB'
#!/usr/bin/env bash
printf 'script=%s\ninterpreter=%s\ncwd=%s\n' "${0##*/}" "$BASH" "$PWD"
for arg in "$@"; do printf 'arg=[%s]\n' "$arg"; done
exit "${STUB_EXIT:-0}"
STUB
done
cat > "$WORK/stubs/uv" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do printf 'arg=[%s]\n' "$arg"; done
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$WORK/stubs/uv"
INTERP="$WORK/interp/testsuite-bash"
ln -s "$BASH" "$INTERP"
ENTRY="$WORK/repo/bin/testsuite"

protects "the public entry point finds its package from outside the repository"

out="$(cd "$WORK" && "$INTERP" "$ENTRY" --help)"
assert_contains "help works outside the repo" "Usage: bin/testsuite" "$out"

protects "shell checks retain their invoking interpreter, arguments and exit status"
out="$("$INTERP" "$ENTRY" run 'two words')"
assert_contains "run selected" "script=run.sh" "$out"
assert_contains "interpreter preserved" "interpreter=$INTERP" "$out"
assert_contains "filter preserved" "arg=[two words]" "$out"
out="$("$INTERP" "$ENTRY")"
assert_contains "default remains shell checks" "script=run.sh" "$out"
STUB_EXIT=7 "$INTERP" "$ENTRY" run > /dev/null
assert_eq "shell failure passes through" "7" "$?"

protects "Python checks use the package lockfile and forward arguments without splitting"
out="$(PATH="$WORK/stubs:$PATH" "$INTERP" "$ENTRY" logtide -k 'two words')"
assert_contains "uv locked environment" $'arg=[run]\narg=[--locked]\narg=[--directory]' "$out"
assert_contains "package directory" "arg=[$WORK/repo/tools/testsuite]" "$out"
assert_contains "pytest selected" $'arg=[python]\narg=[-m]\narg=[pytest]' "$out"
assert_contains "LogTide test path" "arg=[$WORK/repo/tools/testsuite/test_logtide_ship.py]" "$out"
assert_contains "pytest selection preserved" $'arg=[-k]\narg=[two words]' "$out"
out="$(PATH="$WORK/stubs:$PATH" "$INTERP" "$ENTRY" caddy -v)"
assert_contains "Caddy test path" "arg=[$WORK/repo/tools/testsuite/test_caddy_log_redaction.py]" "$out"
assert_contains "unittest argument preserved" "arg=[-v]" "$out"
PATH="$WORK/stubs:$PATH" STUB_EXIT=9 "$INTERP" "$ENTRY" logtide > /dev/null
assert_eq "Python failure passes through" "9" "$?"

protects "build checks resolve repository-relative output from any working directory"
out="$(cd "$WORK" && "$INTERP" "$ENTRY" verify-sentry-build --quick)"
assert_contains "build check selected" "script=verify-sentry-build.sh" "$out"
assert_contains "repository cwd" "cwd=$WORK/repo" "$out"
assert_contains "quick mode preserved" "arg=[--quick]" "$out"

protects "misspelled commands fail rather than silently running another check"
out="$("$INTERP" "$ENTRY" unknown 2>&1)"
status=$?
assert_eq "unknown command exits 64" "64" "$status"
assert_contains "unknown command is actionable" "Unknown testsuite command: unknown" "$out"

finish
