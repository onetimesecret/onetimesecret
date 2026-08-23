# scripts/tests/lib/assert.sh
#
# Sourced, never executed, so it carries no shebang — the
# check-shebang-scripts-are-executable hook would otherwise demand a +x bit
# that would be wrong here. The directive below is what tells shellcheck the
# dialect a shebang would have.
# shellcheck shell=bash
#
# Assertion helpers for the executable shell tests in scripts/tests/*-test.sh.
#
# WHY NOT A FRAMEWORK
#
# This repository has no shell test runner. Tryouts and RSpec are Ruby-only and
# tests/lanes/run boots datastores these scripts never touch; bats would be a
# new toolchain dependency, a new CI install step and a new thing to pin, for a
# handful of pure-text assertions. The existing precedent for asserting on a
# shell script's behaviour is hand-rolled bash — scripts/install-tests/*.sh and
# the scripts/check-*.sh drift guards — so these follow that shape.
#
# FAILURE OUTPUT
#
# Every failure names three things: the assertion, the behaviour it protects,
# and expected vs actual. The reader of a red run is whoever broke it months
# from now, working from the message alone. `protects` is not decoration — an
# assertion whose purpose cannot be stated in one line is usually asserting an
# implementation detail and should be deleted instead.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/assert.sh"
#   protects "why this behaviour matters"
#   assert_eq "label" "$expected" "$actual"
#   finish

ASSERT_RUN=0
ASSERT_FAILED=0
ASSERT_PROTECTS=""
ASSERT_SUITE="${ASSERT_SUITE:-$(basename "${0}")}"

protects() { ASSERT_PROTECTS="$1"; }

_assert_pass() {
  ASSERT_RUN=$((ASSERT_RUN + 1))
  printf '  ok   %s\n' "$1"
}

# Multi-line values are indented and fenced so trailing whitespace and empty
# lines — both load-bearing in the rendered job summary — stay visible.
_assert_block() {
  local title="$1" body="$2"
  printf '       %s:\n' "$title"
  if [ -z "$body" ]; then
    printf '         <empty>\n'
    return 0
  fi
  printf '%s\n' "$body" | sed 's/^/         |/'
}

_assert_fail() {
  local label="$1"
  ASSERT_RUN=$((ASSERT_RUN + 1))
  ASSERT_FAILED=$((ASSERT_FAILED + 1))
  printf '  FAIL %s\n' "$label"
  [ -z "$ASSERT_PROTECTS" ] || printf '       protects: %s\n' "$ASSERT_PROTECTS"
}

assert_eq() { # <label> <expected> <actual>
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    _assert_pass "$label"
    return 0
  fi
  _assert_fail "$label"
  _assert_block "expected" "$expected"
  _assert_block "actual" "$actual"
}

assert_contains() { # <label> <needle> <haystack>
  local label="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*)
      _assert_pass "$label"
      return 0
      ;;
  esac
  _assert_fail "$label"
  _assert_block "expected to contain" "$needle"
  _assert_block "actual" "$haystack"
}

assert_not_contains() { # <label> <needle> <haystack>
  local label="$1" needle="$2" haystack="$3"
  # An empty needle is contained in everything, so a negative assertion on one
  # can never fail. Command substitution strips trailing newlines, which makes
  # `$(printf '\n')` an easy way to write exactly that.
  if [ -z "$needle" ]; then
    _assert_fail "$label"
    printf '       empty needle: this assertion could never fail. Fix the test.\n'
    return 0
  fi
  case "$haystack" in
    *"$needle"*)
      _assert_fail "$label"
      _assert_block "expected NOT to contain" "$needle"
      _assert_block "actual" "$haystack"
      return 0
      ;;
  esac
  _assert_pass "$label"
}

assert_matches() { # <label> <ere> <haystack>
  local label="$1" ere="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -Eq -- "$ere"; then
    _assert_pass "$label"
    return 0
  fi
  _assert_fail "$label"
  _assert_block "expected to match ERE" "$ere"
  _assert_block "actual" "$haystack"
}

# Counts occurrences of a fixed string across whole lines. Used where "exactly
# one row" is the assertion — "at least one" would pass a duplicated row, and a
# duplicated BLOCKED row is a real rendering bug.
assert_line_count() { # <label> <expected-count> <fixed-string> <haystack>
  local label="$1" want="$2" needle="$3" haystack="$4" got
  if [ -z "$needle" ]; then
    _assert_fail "$label"
    printf '       empty needle: every line matches. Fix the test.\n'
    return 0
  fi
  got="$(printf '%s\n' "$haystack" | grep -cF -- "$needle" || true)"
  got="${got//[^0-9]/}"
  if [ "${got:-0}" = "$want" ]; then
    _assert_pass "$label"
    return 0
  fi
  _assert_fail "$label"
  _assert_block "expected ${want} line(s) containing" "$needle"
  _assert_block "found ${got:-0}, in" "$haystack"
}

# Golden comparison. Regenerating with UPDATE_GOLDEN=1 is deliberately a
# separate, explicit act: these goldens encode the anti-silent-success contract,
# and a runner that rewrote them on failure would launder a regression into a
# new baseline.
assert_golden() { # <label> <golden-path> <actual>
  local label="$1" golden="$2" actual="$3" expected=""

  if [ "${UPDATE_GOLDEN:-}" = "1" ]; then
    mkdir -p "$(dirname "$golden")"
    printf '%s\n' "$actual" > "$golden"
    _assert_pass "${label} (golden updated)"
    return 0
  fi

  if [ ! -f "$golden" ]; then
    _assert_fail "$label"
    printf '       missing golden file: %s\n' "$golden"
    printf '       regenerate with: UPDATE_GOLDEN=1 %s\n' "$0"
    return 0
  fi

  expected="$(cat "$golden")"
  if [ "$expected" = "$actual" ]; then
    _assert_pass "$label"
    return 0
  fi

  _assert_fail "$label"
  printf '       golden: %s\n' "$golden"
  printf '       diff (- golden, + actual):\n'
  diff -u "$golden" <(printf '%s\n' "$actual") | tail -n +3 | sed 's/^/         /'
  printf '       if the new output is correct: UPDATE_GOLDEN=1 %s\n' "$0"
}

# Guards against a vacuous test: an extraction whose regex stopped matching
# silently asserts nothing at all, and reads green forever.
assert_at_least() { # <label> <minimum> <actual-count> <what>
  local label="$1" minimum="$2" actual="$3" what="$4"
  if [ "${actual:-0}" -ge "$minimum" ] 2> /dev/null; then
    _assert_pass "$label"
    return 0
  fi
  _assert_fail "$label"
  printf '       expected at least %s %s, found %s\n' "$minimum" "$what" "${actual:-0}"
  printf '       a count this low usually means the extraction stopped matching,\n'
  printf '       which would make every assertion below it pass vacuously.\n'
}

finish() {
  printf '\n%s: %s assertion(s), %s failed\n' \
    "$ASSERT_SUITE" "$ASSERT_RUN" "$ASSERT_FAILED"
  [ "$ASSERT_FAILED" -eq 0 ] || exit 1
  exit 0
}

# --- environment control -----------------------------------------------------
#
# A developer shell that talks to the self-hosted Sentry exports SENTRY_HOST,
# SENTRY_AUTH_TOKEN and SELF_HOSTED_SENTRY_TOKEN. Every one of these scripts
# branches on SENTRY_AUTH_TOKEN being empty — that is the SKIPPED-vs-FAILED
# split the whole design rests on — so a test of the no-credentials path run in
# such a shell silently exercises the credentialed path and passes for the
# wrong reason. Inheriting is never correct here: a test either sets a value or
# asserts its absence.
#
# The list is built from the live environment rather than hard-coded so a
# variable nobody anticipated is scrubbed too, with a floor list so the scrub
# is identical in an already-clean CI shell.
sentry_scrub_args() {
  local name
  {
    # Restricted to well-formed identifiers: a multi-line exported value would
    # otherwise contribute its own lines as bogus variable names.
    env | cut -d= -f1 | grep -E '^[A-Za-z_][A-Za-z0-9_]*$' | grep -E 'SENTRY' || true
    printf '%s\n' SENTRY_AUTH_TOKEN SENTRY_ORG SENTRY_URL SENTRY_HOST \
      SENTRY_PROJECT SENTRY_PROJECTS SENTRY_RELEASE SENTRY_DIST \
      SENTRY_DIST_DIR SENTRY_STATUS_FILE SELF_HOSTED_SENTRY_TOKEN \
      GITHUB_STEP_SUMMARY GITHUB_OUTPUT RUNNER_TEMP
  } | sort -u | while IFS= read -r name; do
    [ -n "$name" ] || continue
    printf -- '-u\n%s\n' "$name"
  done
}
