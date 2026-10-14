#!/usr/bin/env bash
#
# tools/setup/tests/native-bindings-test.sh
#
# Covers the native-binding check that install_node runs after
# `pnpm install` (check_native_bindings in tools/setup/lib.sh).
#
# WHAT THIS PROTECTS
#
#   - Setup fails when a binding the build loads is missing. pnpm reports
#     success after a failed optional-dependency download, so without the
#     check the first sign is `pnpm run build` failing minutes later.
#   - The message names the missing platform package, not the wasm32-wasi
#     fallback that napi-rs loaders put first in the error's cause chain.
#   - A healthy install, and a declared package that is not installed (a
#     production install skips devDependencies), pass without a message.
#   - "a>b" resolves b from a's install location, as pnpm's strict layout
#     requires for a transitive dependency.
#   - A probe entry the dependency graph no longer matches is reported as a
#     stale NATIVE_BINDING_PROBES entry, not as a failed download whose
#     remedy (rm -rf node_modules) would not help.
#
# Runs against stub packages in a temp dir, so it needs node but no
# node_modules from the checkout. The stubs fail with real `require`
# errors, chained the way rolldown's loader chains them.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "${TEST_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PKG_DIR}/../.." && pwd)"
# shellcheck source=tools/testsuite/lib/assert.sh
source "${REPO_ROOT}/tools/testsuite/lib/assert.sh"

if ! command -v node >/dev/null 2>&1; then
  printf '  skip node not found; the native-binding check needs it\n'
  finish
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PROJ="${WORK}/proj"
NM="${PROJ}/node_modules"

# stub DIR — a CommonJS package whose index.js is read from stdin.
stub() {
  mkdir -p "$1"
  printf '{ "name": "%s", "main": "index.js" }\n' "$(basename "$1")" >"$1/package.json"
  cat >"$1/index.js"
}

# The probes' first packages are the checkout's own dependencies.
# not-installed is declared but absent, like a devDependency after a
# production install.
mkdir -p "$PROJ"
cat >"${PROJ}/package.json" <<'JSON'
{
  "name": "stub-checkout",
  "private": true,
  "dependencies": { "loads": "1.0.0", "parent": "1.0.0" },
  "devDependencies": {
    "napi-missing": "1.0.0",
    "imports-napi-missing": "1.0.0",
    "not-installed": "1.0.0"
  }
}
JSON

echo 'module.exports = {};' | stub "${NM}/loads"

# Only reachable from its parent, like a transitive dependency under pnpm.
echo 'module.exports = require("child");' | stub "${NM}/parent"
echo 'module.exports = {};' | stub "${NM}/parent/node_modules/child"

# rolldown's loader: platform file, platform package, wasi file, wasi
# package, each failure the cause of the next, under one generic error.
stub "${NM}/napi-missing" <<'JS'
const platform = process.platform + "-" + process.arch;
let cause;
for (const spec of [
  "./stub." + platform + ".node",
  "@stub/binding-" + platform + "-gnu",
  "./stub.wasi.cjs",
  "@stub/binding-wasm32-wasi",
]) {
  try { require(spec); } catch (error) { error.cause = cause; cause = error; }
}
throw new Error("Cannot find native binding.", { cause });
JS
echo 'module.exports = require("napi-missing");' | stub "${NM}/imports-napi-missing"

# lightningcss's loader: falls back to a relative file and drops the first
# error, so no package name survives.
stub "${NM}/parent/node_modules/css-missing" <<'JS'
const platform = process.platform + "-" + process.arch;
try { require("stub-css-" + platform); } catch { require("../stub-css." + platform + ".node"); }
JS

PLATFORM="$(node -p 'process.platform + "-" + process.arch')"

# check PROBES FUNCTION — run FUNCTION from lib.sh in the stub checkout
# with NATIVE_BINDING_PROBES set to PROBES. Sets rc and out.
check() {
  # shellcheck source=tools/setup/lib.sh
  out="$(cd "$PROJ" && source "${PKG_DIR}/lib.sh" && NATIVE_BINDING_PROBES="$1" && "$2" 2>&1)"
  rc=$?
}

protects "a healthy install, a transitive dependency and an absent package pass without a message"
check "loads parent>child not-installed" native_binding_failures
assert_eq "no failures reported" "" "$out"
check "loads parent>child not-installed" check_native_bindings
assert_eq "healthy install: exit status" "0" "$rc"
assert_contains "healthy install: says so" "OK:   Native bindings" "$out"

protects "a missing binding fails setup, naming the platform package"
check "napi-missing" check_native_bindings
assert_eq "missing binding: exit status" "1" "$rc"
assert_contains "names the platform package" "@stub/binding-${PLATFORM}-gnu" "$out"
assert_not_contains "does not name the wasi fallback" "wasm32-wasi" "$out"
assert_contains "gives a fix that restores the binding" "rm -rf node_modules" "$out"

protects "one missing binding reached through two packages is reported once"
check "napi-missing imports-napi-missing" native_binding_failures
assert_eq "one line naming both" \
  "binding	@stub/binding-${PLATFORM}-gnu	napi-missing, imports-napi-missing" "$out"

protects "a loader that drops the package name still fails, with its own error"
check "parent>css-missing" native_binding_failures
assert_eq "the loader's own error when no package name survives" \
  "binding	Cannot find module '../stub-css.${PLATFORM}.node'	parent > css-missing" "$out"

protects "a stale probe entry is diagnosed as one, not as a failed download"
check "removed parent>gone" native_binding_failures
assert_eq "both kinds of stale entry" \
  "stale	removed is not a dependency in package.json	removed
stale	gone does not resolve from parent	parent > gone" "$out"
check "removed parent>gone" check_native_bindings
assert_eq "stale entry: exit status" "1" "$rc"
assert_contains "names the list to update" "NATIVE_BINDING_PROBES in tools/setup/lib.sh" "$out"
assert_not_contains "does not blame a download" "rm -rf node_modules" "$out"

protects "a missing binding and a stale entry are both reported"
check "napi-missing parent>gone" check_native_bindings
assert_eq "both: exit status" "1" "$rc"
assert_contains "both: the binding fix" "rm -rf node_modules" "$out"
assert_contains "both: the stale entry" "gone does not resolve from parent" "$out"

finish
