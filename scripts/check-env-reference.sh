#!/usr/bin/env bash
#
# check-env-reference.sh  (install-onboarding C9 / QS-11)
#
# .env.reference claims to document every supported environment variable —
# this makes that claim CI-checked instead of aspirational. Dependency-free
# (grep/sed/sort/comm only).
#
# A variable counts as "consumed" when it appears in any of:
#   - app code:   ENV['X'] / ENV.fetch('X'  under lib/, apps/, etc/, config.ru
#   - .env.example (active or commented keys)
#   - README.md   (docker `-e X=` flags or `X=` assignments in code blocks)
#
# Every consumed variable must appear in .env.reference (active or commented
# key), or be listed in scripts/env-reference-ignore.txt with a reason.
# This is a RATCHET: introducing a new env var means documenting it in
# .env.reference or explicitly ignoring it — silent drift fails CI.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

IGNORE_FILE="scripts/env-reference-ignore.txt"

[[ -f .env.reference ]] || { echo "FAIL: .env.reference not found" >&2; exit 1; }
[[ -f "$IGNORE_FILE" ]] || { echo "FAIL: $IGNORE_FILE not found" >&2; exit 1; }

tmp_consumed=$(mktemp) tmp_documented=$(mktemp) tmp_ignored=$(mktemp) tmp_allowed=$(mktemp)
trap 'rm -f "$tmp_consumed" "$tmp_documented" "$tmp_ignored" "$tmp_allowed"' EXIT

# --- Consumed variables -------------------------------------------------
{
  # Ruby: ENV['X'], ENV["X"], ENV.fetch('X', ...), ENV.fetch("X", ...)
  grep -rEoh "ENV(\.fetch\(|\[)['\"][A-Z][A-Z0-9_]+['\"]" lib apps etc config.ru 2>/dev/null \
    | sed -E "s/^ENV(\.fetch\(|\[)['\"]([A-Z][A-Z0-9_]+)['\"].*/\2/"

  # .env.example: active and commented keys
  sed -n -E 's/^#?([A-Z][A-Z0-9_]+)=.*/\1/p' .env.example

  # README: docker -e flags and VAR= assignments in code blocks
  { grep -Eoh -- '-e [A-Z][A-Z0-9_]+=' README.md || true; } | grep -Eo '[A-Z][A-Z0-9_]+'
  sed -n -E 's/^[[:space:]]*(export )?([A-Z][A-Z0-9_]+)=.*/\2/p' README.md
} | sort -u > "$tmp_consumed"

# --- Documented + ignored -----------------------------------------------
sed -n -E 's/^#?([A-Z][A-Z0-9_]+)=.*/\1/p' .env.reference | sort -u > "$tmp_documented"
sed -e 's/#.*$//' -e 's/[[:space:]]//g' "$IGNORE_FILE" | grep -E '^[A-Z][A-Z0-9_]+$' | sort -u > "$tmp_ignored"
sort -u "$tmp_documented" "$tmp_ignored" > "$tmp_allowed"

# --- Compare -------------------------------------------------------------
missing=$(comm -23 "$tmp_consumed" "$tmp_allowed")

if [[ -n "$missing" ]]; then
  count=$(echo "$missing" | wc -l | tr -d ' ')
  echo "FAIL: $count consumed env var(s) neither documented in .env.reference nor listed in $IGNORE_FILE:" >&2
  echo "$missing" | sed 's/^/  /' >&2
  echo "" >&2
  echo "Document each in .env.reference (a commented '#VAR=' line with a short" >&2
  echo "explanation is fine), or add it to $IGNORE_FILE with a reason." >&2
  exit 1
fi

# Advisory only: ignored vars that are now documented can leave the ignore file.
stale=$(comm -12 "$tmp_documented" "$tmp_ignored")
if [[ -n "$stale" ]]; then
  echo "NOTE: documented in .env.reference AND still in $IGNORE_FILE (remove from the ignore file):"
  echo "$stale" | sed 's/^/  /'
fi

echo "PASS: every consumed env var is documented in .env.reference or explicitly ignored"
echo "  ($(wc -l < "$tmp_consumed" | tr -d ' ') consumed, $(wc -l < "$tmp_documented" | tr -d ' ') documented, $(wc -l < "$tmp_ignored" | tr -d ' ') ignored)"
exit 0
