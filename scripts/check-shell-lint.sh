#!/usr/bin/env bash
#
# scripts/check-shell-lint.sh
#
# Runs shellcheck over every tracked shell script and actionlint over every
# workflow, and fails on findings that are NOT in the recorded baseline.
#
# WHY A BASELINE AND NOT A CLEAN SLATE
#
# Neither tool ran anywhere in this repository before, so both start with
# pre-existing findings — 8 for shellcheck, 90 for actionlint, most of them the
# deliberate unquoted expansions that pass a space-separated list as separate
# arguments. Fixing all of them is not this change's job, and a lane that lands
# red teaches everyone to ignore it, which is the same cry-wolf failure the
# Sentry status reporting exists to end. So: record what is there, fail on
# anything new. Same shape as .rubocop_todo.yml, which this repo already uses
# for exactly this purpose.
#
# The baseline is a per-file, per-rule COUNT rather than a list of line
# numbers, because line numbers churn on every edit above them and a guard that
# goes red for unrelated reasons gets muted.
#
# Usage:
#   scripts/check-shell-lint.sh            # assert no new findings
#   scripts/check-shell-lint.sh --update   # re-record the baselines
#   scripts/check-shell-lint.sh --list     # print current findings, no verdict
#
# Findings that disappear are reported but do not fail: an unrelated PR that
# happens to clean one up should not be blocked. Re-run with --update to tighten
# the baseline when that happens.
#
# Remediation text quoted to the operator contains a literal '$'.
# shellcheck disable=SC2016
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

BASELINE_DIR="${REPO_ROOT}/.github/lint-baseline"
SHELLCHECK_BASELINE="${BASELINE_DIR}/shellcheck.tsv"
ACTIONLINT_BASELINE="${BASELINE_DIR}/actionlint.tsv"

# Pinned in .github/workflows/static-analysis.yml. Both tools change their
# finding sets between versions, so a baseline recorded under one version is
# not meaningful under another.
SHELLCHECK_VERSION="0.11.0"
ACTIONLINT_VERSION="1.7.12"

# Repo-wide floor. -S style would add several hundred pre-existing style
# findings to the baseline for no present benefit.
SHELLCHECK_SEVERITY="warning"

# Directories held to the stricter floor with no baseline at all: the CI
# reporting scripts and their tests. They are clean at `style` today and the
# point of the lane is to keep the newest code the tidiest.
STRICT_GLOBS=("scripts/ci" "scripts/tests")

MODE="check"
case "${1:-}" in
  --update) MODE="update" ;;
  --list) MODE="list" ;;
  -h | --help)
    grep '^#' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  '') ;;
  *)
    echo "unknown arg: $1" >&2
    exit 64
    ;;
esac

fail() {
  echo "$*" >&2
  exit 1
}

command -v shellcheck > /dev/null 2>&1 || fail \
  "shellcheck not found. Install it (brew install shellcheck) or run this in CI."
command -v actionlint > /dev/null 2>&1 || fail \
  "actionlint not found. Install it (brew install actionlint) or run this in CI."

# A version mismatch does not stop the run — a maintainer with a slightly
# different local build should still get useful output — but it is the first
# thing to suspect when the baseline diff makes no sense.
check_version() { # <tool> <found> <pinned>
  [ "$2" = "$3" ] || printf \
    'note: %s %s here, %s pinned in CI — finding sets differ between versions.\n' \
    "$1" "$2" "$3" >&2
}
check_version shellcheck \
  "$(shellcheck --version | awk '/^version:/ { print $2 }')" "$SHELLCHECK_VERSION"
check_version actionlint \
  "$(actionlint --version | head -n1)" "$ACTIONLINT_VERSION"

# --- finding collection ------------------------------------------------------
#
# Both collectors emit "<file>\t<rule>" per finding; counting happens once, in
# fingerprint().

shellcheck_findings() {
  local -a files=()
  mapfile -t files < <(git ls-files --cached --others --exclude-standard '*.sh')
  [ "${#files[@]}" -gt 0 ] || return 0
  shellcheck -f gcc -S "$SHELLCHECK_SEVERITY" "${files[@]}" 2> /dev/null \
    | sed -nE 's|^([^:]+):[0-9]+:[0-9]+: [a-z]+: .* \[(SC[0-9]+)\]$|\1\t\2|p'
}

# actionlint's own findings keep their rule id. The ones it produces by running
# SHELLCHECK over `run:` blocks are recorded as shellcheck:SCnnnn — the bare
# "[shellcheck]" tag would lump an unquoted expansion together with a mangling
# `read` and let one be traded for the other under a single count.
#
# (A comment line here must not begin with the tool's own name: shellcheck reads
# a leading `# <toolname> ...` comment as a directive and errors on SC1072.)
actionlint_findings() {
  actionlint -no-color -oneline 2> /dev/null | sed -nE \
    -e 's|^([^:]+):[0-9]+:[0-9]+: shellcheck reported issue in this script: (SC[0-9]+):.*\[shellcheck\]$|\1\tshellcheck:\2|p' \
    -e 's|^([^:]+):[0-9]+:[0-9]+: .* \[([a-z0-9-]+)\]$|\1\t\2|p'
}

fingerprint() { sort | uniq -c | awk '{ printf "%s\t%s\t%s\n", $2, $3, $1 }' | sort; }

# --- baseline comparison -----------------------------------------------------

compare() { # <label> <baseline-file> <current-fingerprints>
  local label="$1" baseline="$2" current="$3"
  local file rule count want line
  local new=0 grown=0 shrunk=0 gone=0

  local baseline_body
  baseline_body="$(grep -v '^#' "$baseline" 2> /dev/null | grep -v '^[[:space:]]*$')"

  while IFS=$'\t' read -r file rule count; do
    [ -n "${file:-}" ] || continue
    want="$(printf '%s\n' "$baseline_body" \
      | awk -F'\t' -v f="$file" -v r="$rule" '$1 == f && $2 == r { print $3; exit }')"
    if [ -z "$want" ]; then
      printf '%s: NEW  %s  %s  x%s\n' "$label" "$file" "$rule" "$count"
      new=$((new + 1))
    elif [ "$count" -gt "$want" ]; then
      printf '%s: MORE %s  %s  %s -> %s\n' "$label" "$file" "$rule" "$want" "$count"
      grown=$((grown + 1))
    elif [ "$count" -lt "$want" ]; then
      printf '%s: less %s  %s  %s -> %s (baseline can be tightened)\n' \
        "$label" "$file" "$rule" "$want" "$count"
      shrunk=$((shrunk + 1))
    fi
  done <<< "$current"

  while IFS=$'\t' read -r file rule count; do
    [ -n "${file:-}" ] || continue
    line="$(printf '%s\n' "$current" \
      | awk -F'\t' -v f="$file" -v r="$rule" '$1 == f && $2 == r { print; exit }')"
    if [ -z "$line" ]; then
      printf '%s: gone %s  %s  x%s (baseline entry is stale)\n' \
        "$label" "$file" "$rule" "$count"
      gone=$((gone + 1))
    fi
  done <<< "$baseline_body"

  if [ "$new" -gt 0 ] || [ "$grown" -gt 0 ]; then
    printf '%s: %s new finding kind(s), %s increased count(s).\n' "$label" "$new" "$grown"
    return 1
  fi

  printf '%s: no new findings (%s cleaned up, %s stale baseline entr(y|ies)).\n' \
    "$label" "$shrunk" "$gone"
  return 0
}

write_baseline() { # <path> <header> <fingerprints>
  mkdir -p "$(dirname "$1")"
  {
    printf '%s\n' "$2"
    printf '%s\n' "$3"
  } > "$1"
  printf 'wrote %s\n' "$1"
}

SHELLCHECK_HEADER="# .github/lint-baseline/shellcheck.tsv
#
# Pre-existing shellcheck findings, accepted at the time the static-analysis
# lane was introduced. Regenerate with: scripts/check-shell-lint.sh --update
#
# Format: <file><TAB><rule><TAB><count>. A NEW file/rule pair, or a count above
# the recorded one, fails the lane. A lower count passes and is reported so the
# baseline can be tightened.
#
# Severity floor: ${SHELLCHECK_SEVERITY}. scripts/ci and scripts/tests are held to
# 'style' with no baseline; see scripts/check-shell-lint.sh.
#
# These are debt, not exemptions. Nothing here is unfixable — SC2034 is an
# unused variable, SC2164 is an unchecked cd, SC2155 masks an exit status.
# Fixing one and re-running --update is always in scope."

ACTIONLINT_HEADER="# .github/lint-baseline/actionlint.tsv
#
# Pre-existing actionlint findings, accepted at the time the static-analysis
# lane was introduced. Regenerate with: scripts/check-shell-lint.sh --update
#
# Format: <file><TAB><rule><TAB><count>. Rules prefixed 'shellcheck:' come from
# actionlint running shellcheck over a 'run:' block.
#
# The large SC2086 counts are mostly deliberate: this repo passes
# space-separated lists (bake tags, sentry project flags, the Sentry expected
# component list) through unquoted expansions ON PURPOSE, because each element
# must become its own argument. Quoting them would be a regression, not a fix —
# scripts/tests/sentry-components-drift-test.sh asserts one of them stays
# unquoted. They are baselined rather than disabled inline so the count is
# visible and a NEW unquoted expansion still has to be justified.
#
# syntax-check on build-and-publish-oci-images.yml is the empty '' branch of a
# workflow_dispatch choice input, which is how that input expresses 'not set'."

# --- run ---------------------------------------------------------------------

sc_current="$(shellcheck_findings | fingerprint)"
al_current="$(actionlint_findings | fingerprint)"

if [ "$MODE" = "list" ]; then
  printf '%s\n' "$sc_current"
  printf '%s\n' "$al_current"
  exit 0
fi

if [ "$MODE" = "update" ]; then
  write_baseline "$SHELLCHECK_BASELINE" "$SHELLCHECK_HEADER" "$sc_current"
  write_baseline "$ACTIONLINT_BASELINE" "$ACTIONLINT_HEADER" "$al_current"
  exit 0
fi

rc=0

for baseline in "$SHELLCHECK_BASELINE" "$ACTIONLINT_BASELINE"; do
  [ -f "$baseline" ] || fail \
    "missing baseline ${baseline}. Create it with: scripts/check-shell-lint.sh --update"
done

compare shellcheck "$SHELLCHECK_BASELINE" "$sc_current" || rc=1
compare actionlint "$ACTIONLINT_BASELINE" "$al_current" || rc=1

# The strict tier. No baseline, so the message has to stand alone: these
# directories are expected to be clean and a finding here is the finding.
strict_out=""
for glob in "${STRICT_GLOBS[@]}"; do
  mapfile -t strict_files < <(git ls-files --cached --others --exclude-standard "${glob}/*.sh" "${glob}/**/*.sh")
  [ "${#strict_files[@]}" -gt 0 ] || continue
  strict_out="${strict_out}$(shellcheck -f gcc -S style "${strict_files[@]}" 2>&1)"
done

if [ -n "$strict_out" ]; then
  printf 'shellcheck (strict, no baseline): findings in %s\n' "${STRICT_GLOBS[*]}"
  printf '%s\n' "$strict_out"
  printf 'These directories are held to -S style with no baseline. Fix the finding,\n'
  printf 'or add a targeted `# shellcheck disable=SCnnnn` with a reason above it.\n'
  rc=1
fi

if [ "$rc" -eq 0 ]; then
  printf '\nshell lint: clean against the recorded baselines.\n'
else
  printf '\nshell lint: FAILED. If a finding is intentional, either fix it, add a\n'
  printf 'targeted `# shellcheck disable=SCnnnn` with a reason, or — for genuinely\n'
  printf 'accepted debt — run scripts/check-shell-lint.sh --update and explain the\n'
  printf 'new baseline entry in the commit message.\n'
fi

exit "$rc"
