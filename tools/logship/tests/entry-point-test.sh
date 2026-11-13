#!/usr/bin/env bash
# Test root and compatibility entry points without network or log ingestion.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=tools/testsuite/lib/assert.sh
source "$ROOT/tools/testsuite/lib/assert.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/repo/bin" "$WORK/repo/scripts" "$WORK/stubs"
cp "$ROOT/bin/logship" "$WORK/repo/bin/logship"
cp "$ROOT/scripts/logtide-ship.py" "$WORK/repo/scripts/logtide-ship.py"
cat > "$WORK/stubs/uv" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do printf 'arg=[%s]\n' "$arg"; done
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$WORK/stubs/uv"

protects "the root entry point selects the locked package outside the repository"
out="$(cd "$WORK" && PATH="$WORK/stubs:$PATH" bash "$WORK/repo/bin/logship" follow 'two words' --mode caddy)"
assert_contains "locked runtime" $'arg=[run]\narg=[--locked]\narg=[--project]' "$out"
assert_contains "package path" "arg=[$WORK/repo/tools/logship]" "$out"
assert_contains "command selected" $'arg=[logship]\narg=[follow]' "$out"
assert_contains "arguments preserved" $'arg=[two words]\narg=[--mode]\narg=[caddy]' "$out"
PATH="$WORK/stubs:$PATH" STUB_EXIT=7 bash "$WORK/repo/bin/logship" batch service >/dev/null
assert_eq "exit status preserved" 7 "$?"

protects "a missing managed runtime fails without a bare-Python fallback"
PATH=/usr/bin:/bin bash "$WORK/repo/bin/logship" --help >/dev/null 2>&1
assert_eq "missing uv" 69 "$?"

protects "the legacy Python command forwards arguments, input and exit status"
cat > "$WORK/repo/bin/logship" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do printf 'arg=[%s]\n' "$arg"; done
cat
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$WORK/repo/bin/logship"
out="$(printf 'input-line\n' | python3 "$WORK/repo/scripts/logtide-ship.py" batch 'two words')"
assert_contains "legacy arguments preserved" $'arg=[batch]\narg=[two words]' "$out"
assert_contains "legacy stdin preserved" 'input-line' "$out"
STUB_EXIT=9 python3 "$WORK/repo/scripts/logtide-ship.py" batch service </dev/null >/dev/null
assert_eq "legacy exit status preserved" 9 "$?"

finish
