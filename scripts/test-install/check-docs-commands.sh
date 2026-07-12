#!/usr/bin/env bash
#
# scripts/test-install/check-docs-commands.sh
#
# Docs-command drift guard (install-onboarding testing-strategy §2c).
#
# The failure mode this catches: a documented setup command references a
# script, bin/ entrypoint, or pnpm target that has since been renamed or
# removed, so the docs tell a fresh user to run something that no longer
# exists. This is a 10-line guard, deliberately: it checks that referenced
# artifacts EXIST, not that their output matches (output-matching doc tests
# rot on timestamps/versions — see the strategy doc's rejection of
# runme/byexample/tesh).
#
# Runnable locally (`scripts/test-install/check-docs-commands.sh`) and in CI
# (docs-command-drift.yml) — the same artifact, so the two cannot diverge.
#
# Exit 0 = every documented command's target exists; exit 1 = drift found.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail=0
note() { printf '  %s\n' "$1"; }
bad()  { printf 'DRIFT: %s\n' "$1" >&2; fail=1; }

# --- 1. Documented scripts / entrypoints that must exist and be executable ---
#
# Each of these is pasted verbatim in README.md or docs/development and is a
# file in the repo. If a rename lands without updating the docs, this trips.
declare -a EXECUTABLES=(
  bin/setup
  install.sh
  install-dev.sh
  install-test.sh
  bin/dev
  bin/ots
)
echo "Checking documented scripts/entrypoints exist and are executable..."
for f in "${EXECUTABLES[@]}"; do
  if [[ ! -f "$f" ]]; then
    bad "documented command references '$f' but it does not exist"
  elif [[ ! -x "$f" ]]; then
    bad "'$f' exists but is not executable (docs paste it as './$f')"
  else
    note "OK: $f"
  fi
done

# --- 2. Documented pnpm targets that must be defined in package.json ---------
#
# README/docs tell contributors to run these; a script-rename in package.json
# would silently break the documented flow.
declare -a PNPM_TARGETS=(
  build
  test:rspec:fast
  locales:sync
  schemas:json:generate
)
echo "Checking documented pnpm run targets are defined..."
for t in "${PNPM_TARGETS[@]}"; do
  # jq isn't guaranteed on every runner; a node one-liner reads package.json
  # authoritatively (a grep would false-match target names inside other values).
  if node -e "process.exit(require('./package.json').scripts['$t'] ? 0 : 1)"; then
    note "OK: pnpm run $t"
  else
    bad "documented command 'pnpm run $t' has no matching package.json script"
  fi
done

# --- 3. Every ./install*.sh and bin/<x> literally referenced in the
#        contributor-facing docs exists ---------------------------------------
#
# Belt-and-suspenders: catch any NEW documented command we forgot to add to
# the curated list above. Extracts `./install*.sh` and `bin/<word>` tokens
# from the docs a fresh contributor reads and asserts each resolves to a
# real file.
for doc in README.md CONTRIBUTING.md docs/development/README.md; do
  [[ -f "$doc" ]] || continue
  echo "Cross-checking $doc references against the tree..."
  # shellcheck disable=SC2013
  for ref in $(grep -oE '(\./install[a-z-]*\.sh|bin/[a-z][a-z0-9_-]*)' "$doc" | sort -u); do
    path="${ref#./}"
    if [[ -e "$path" ]]; then
      note "OK: $doc references $ref"
    else
      bad "$doc references '$ref' but it does not exist"
    fi
  done
done

if (( fail )); then
  echo "" >&2
  echo "Docs-command drift detected: a documented command points at something" >&2
  echo "that no longer exists. Update the docs or restore the target." >&2
  exit 1
fi
echo "All documented commands resolve to real targets."
