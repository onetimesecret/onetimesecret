#!/usr/bin/env bash
#
# scripts/tests/sentry-status-sanitize-test.sh
#
# Covers the two text-neutralising functions in scripts/ci/sentry-status.sh:
# sanitize() at the record seam and md_code() at the render seam.
#
# WHAT THIS PROTECTS
#
# Both functions exist because their outputs are PUBLISHED. This repository is
# public, so annotations and the job summary are world-readable, and detail
# strings can carry sentry-cli, docker and Sentry-server text that a remote
# controls. Two distinct hazards:
#
#   sanitize  a detail must not be able to forge a workflow command (`::`), and
#             must not leave a PARTIAL secret in the output. GitHub masks a
#             registered secret by EXACT value only, so a truncation that
#             shears a token publishes an unmaskable fragment in the clear.
#             That is why the length cap cuts on whitespace and drops the
#             straddling token whole.
#   md_code   the summary is GFM. A live link or a Camo-proxied <img> planted
#             in a table cell is a beacon on this repo's public run page. The
#             code span disarms links, images and HTML in one move, which only
#             holds if the fence outruns the longest backtick run it wraps and
#             pipes stay escaped.
#
# HOW THE FUNCTIONS ARE REACHED
#
# sentry-status.sh calls main and exits at the bottom of the file, so sourcing
# it whole would terminate this test. The entry point is stripped into a temp
# copy instead. That coupling is checked, not assumed: if the tail of the
# script stops looking like an entry point, this file fails loudly rather than
# sourcing something that no longer defines what it is about to assert on.
#
# Single-quoted '$' and backticks are the subject matter: expected md_code
# output is literal backtick fences, and the sed pattern matches the script's
# literal `main "$@"` line.
# shellcheck disable=SC2016
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assert.sh
source "${TEST_DIR}/lib/assert.sh"

STATUS_SCRIPT="${REPO_ROOT}/scripts/ci/sentry-status.sh"
CAP=700 # the length cap sanitize() applies

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sentry-sanitize-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

LIB="${WORK}/sentry-status-lib.sh"
sed '/^main "\$@"$/,$d' "$STATUS_SCRIPT" > "$LIB"

if grep -q '^main "\$@"$' "$LIB" || [ "$(wc -c < "$LIB")" -eq "$(wc -c < "$STATUS_SCRIPT")" ]; then
  printf 'FAIL: could not strip the entry point from %s\n' "$STATUS_SCRIPT" >&2
  printf '      This test sources the script to call sanitize() and md_code()\n' >&2
  printf '      directly, which requires the file to end with the `main "$@"`\n' >&2
  printf '      invocation. Update the sed above to match the new tail.\n' >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$LIB"

for fn in sanitize md_code; do
  if ! declare -F "$fn" > /dev/null; then
    printf 'FAIL: %s() is not defined after sourcing %s\n' "$fn" "$STATUS_SCRIPT" >&2
    printf '      Every assertion below would otherwise pass vacuously.\n' >&2
    exit 1
  fi
done

printf '%s\n' "$ASSERT_SUITE"

# --- sanitize: workflow-command forgery --------------------------------------

printf '\nsanitize: workflow-command forgery\n'
protects "the runner parses ::commands:: out of the log stream, so a remote-controlled detail that keeps a literal '::' can forge an annotation or run ::add-mask:: / ::stop-commands::"

assert_eq "a forged error annotation is defanged" \
  ";;error;;forged" "$(sanitize '::error::forged')"
assert_eq "::add-mask:: is defanged" \
  ";;add-mask;;value" "$(sanitize '::add-mask::value')"
assert_not_contains "no literal :: survives anywhere in the output" \
  "::" "$(sanitize 'lead ::stop-commands::token trail ::endgroup::')"
assert_not_contains "odd-length colon runs leave no :: either" \
  "::" "$(sanitize ':::::')"

printf '\nsanitize: line breaks\n'
protects "the runner matches a workflow command on any line whose first non-space character starts '::', so a detail that can inject a newline can start a fresh line and forge one regardless of the :: rewrite"

assert_eq "newline, carriage return and tab each become one space" \
  "a b c d" "$(sanitize "$(printf 'a\nb\rc\td')")"
# Counted rather than string-matched: command substitution strips trailing
# newlines, so a "does not contain \n" assertion would test an empty needle.
assert_eq "a multi-line detail collapses to a single line" \
  "0" "$(sanitize "$(printf 'x\ny\nz')" | wc -l | tr -d ' ')"

printf '\nsanitize: multiple arguments\n'
protects "record() forwards its remaining arguments as \$*, so a detail split across arguments must join rather than silently drop everything after the first"

assert_eq "arguments are joined on a space" "one two three" "$(sanitize one two three)"
assert_eq "empty input stays empty" "" "$(sanitize '')"
assert_eq "no argument at all stays empty" "" "$(sanitize)"

# --- sanitize: truncation ----------------------------------------------------
#
# The security-relevant property is NOT "the output is short". It is that a
# token is either entirely present — and therefore maskable — or entirely gone.

printf '\nsanitize: the length cap does not shear a token\n'
protects "GitHub redacts a secret only when the text matches the registered value exactly; a sheared prefix is unmaskable and publishes in the clear on a public repo"

secret="glpat-SUPERSECRET-TOKEN-VALUE-0123456789"
# The token has to START BEFORE the cap and END AFTER it — that is the only
# offset a character-wise cut slices through. Ten-character words repeated to
# exactly CAP-10 put the token's first ten characters inside the cut and the
# rest outside; the trailing space in the filler leaves a real whitespace
# boundary before it, so the whole-token drop has somewhere to cut back to.
# (Padding that does not land the token across the boundary makes every
# assertion below pass under a mid-token cut too, proving nothing.)
lead="$(printf 'abcdefghi %.0s' $(seq 1 $(((CAP - 10) / 10))))"
straddling="${lead}${secret} trailing words here"

if [ "${#lead}" -ne $((CAP - 10)) ] || [ $((${#lead} + ${#secret})) -le "$CAP" ]; then
  printf 'FAIL: the truncation fixture does not straddle the cap.\n' >&2
  printf '      lead=%s secret=%s cap=%s\n' "${#lead}" "${#secret}" "$CAP" >&2
  exit 1
fi

out="$(sanitize "$straddling")"
assert_contains "the cap fired" "[…truncated]" "$out"
assert_not_contains "the straddling token is dropped WHOLE, not sheared" \
  "$secret" "$out"
assert_not_contains "not even a prefix of it survives" "glpat-SUPER" "$out"
assert_not_contains "not even the leading fragment survives" "glpat" "$out"
assert_not_contains "nothing after the cut leaks either" "trailing words" "$out"

printf '\nsanitize: an overlong token with no whitespace\n'
protects "a single unbroken token longer than the cap has no whitespace boundary to cut on, so the only safe answer is to publish none of it"

blob="$(printf 'Z%.0s' $(seq 1 $((CAP + 100))))"
out="$(sanitize "$blob")"
assert_eq "everything but the marker is dropped" \
  "[…truncated]" "$(printf '%s' "$out" | tr -d ' ')"
assert_not_contains "no fragment of the token survives" "ZZZZZZZZZZ" "$out"

printf '\nsanitize: the cap boundary\n'
protects "an off-by-one here either truncates details that were fine (losing diagnostics on a self-hosted Sentry where diagnostic value is the point) or lets an over-long one through"

at_cap="$(printf 'y%.0s' $(seq 1 "$CAP"))"
assert_eq "exactly at the cap is passed through untouched" \
  "$at_cap" "$(sanitize "$at_cap")"
assert_not_contains "exactly at the cap is not marked truncated" \
  "truncated" "$(sanitize "$at_cap")"
assert_contains "one character over the cap truncates" \
  "[…truncated]" "$(sanitize "${at_cap}z")"

# --- md_code -----------------------------------------------------------------
#
# The inertness of a code span is a structural property: the payload is wholly
# enclosed by a backtick fence longer than any run inside it. Asserting that
# structure is stronger than string-matching one expected output, because it
# holds for inputs nobody thought to enumerate.

longest_backtick_run() { # <text> -> longest consecutive ` count
  local text="$1" i ch run=0 longest=0
  for ((i = 0; i < ${#text}; i++)); do
    ch="${text:i:1}"
    if [ "$ch" = '`' ]; then
      run=$((run + 1))
      [ "$run" -le "$longest" ] || longest="$run"
    else
      run=0
    fi
  done
  printf '%s' "$longest"
}

assert_inert_code_span() { # <label> <original> <md_code output>
  local label="$1" original="$2" out="$3"
  local lead trail payload

  lead="${out%%[!\`]*}"
  trail="${out##*[!\`]}"
  payload="${out#"$lead"}"
  payload="${payload%"$trail"}"

  if [ -z "$lead" ] || [ "${#lead}" -ne "${#trail}" ]; then
    _assert_fail "$label"
    _assert_block "input" "$original"
    _assert_block "output is not a balanced code span" "$out"
    return 0
  fi

  if [ "${#lead}" -le "$(longest_backtick_run "$payload")" ]; then
    _assert_fail "$label"
    _assert_block "input" "$original"
    _assert_block "fence is not longer than the longest run inside it" "$out"
    return 0
  fi

  case "$payload" in
    *'|'*)
      case "$payload" in
        *'\|'*) ;;
        *)
          _assert_fail "$label"
          _assert_block "unescaped pipe would split the table row" "$out"
          return 0
          ;;
      esac
      ;;
  esac

  _assert_pass "$label"
}

printf '\nmd_code: the plain cases\n'
protects "the code span is what makes a remote-controlled detail inert in the public job summary; an empty or unwrapped cell means the neutralisation did not happen"

assert_eq "empty detail renders as an em dash, not an empty span" "—" "$(md_code '')"
assert_eq "no argument renders as an em dash" "—" "$(md_code)"
assert_eq "plain text gets a one-backtick fence" '`plain text`' "$(md_code 'plain text')"

printf '\nmd_code: markup that would otherwise be live\n'
protects "a link or a Camo-proxied <img> planted in a table cell is a beacon on this public repository's run page, fired by anyone who opens the run"

link='[click me](https://attacker.example/x)'
assert_inert_code_span "a markdown link is enclosed" "$link" "$(md_code "$link")"
assert_contains "the link text is preserved for the reader" \
  "$link" "$(md_code "$link")"

img='<img src="https://attacker.example/beacon.png">'
assert_inert_code_span "an img tag is enclosed" "$img" "$(md_code "$img")"

ref='![x](https://attacker.example/b.png "t")'
assert_inert_code_span "an image reference is enclosed" "$ref" "$(md_code "$ref")"

html='<a href="https://attacker.example">x</a><script>alert(1)</script>'
assert_inert_code_span "raw HTML is enclosed" "$html" "$(md_code "$html")"

printf '\nmd_code: pipes\n'
protects "GFM resolves table cell boundaries BEFORE it parses inline spans, so a bare pipe splits the row even inside a code span — a detail could otherwise forge extra columns or a whole extra row"

out="$(md_code 'a | b | c')"
assert_eq "every pipe is escaped" '`a \| b \| c`' "$out"
assert_inert_code_span "pipes plus a span" 'a | b | c' "$out"
assert_eq "a multi-pipe detail stays on one line" \
  "0" "$(md_code 'a | b | c' | wc -l | tr -d ' ')"

printf '\nmd_code: backtick runs\n'
protects "a fence no longer than a run inside it closes early, and everything after that run escapes the span and renders live"

assert_eq "one backtick inside forces a two-backtick fence" \
  '``a`b``' "$(md_code 'a`b')"
assert_eq "a run of three forces a fence of four" \
  '````a```b````' "$(md_code 'a```b')"
assert_inert_code_span "a long run stays enclosed" 'x`````y' "$(md_code 'x`````y')"

printf '\nmd_code: content that starts or ends in a backtick\n'
protects "GFM 6.1 strips one leading and one trailing space from a code span, so without the pad a boundary backtick merges into the fence and the span breaks open"

out="$(md_code '`leading')"
assert_eq "a leading backtick gets a pad space" '`` `leading ``' "$out"
assert_inert_code_span "leading backtick stays enclosed" '`leading' "$out"

out="$(md_code 'trailing`')"
assert_eq "a trailing backtick gets a pad space" '`` trailing` ``' "$out"
assert_inert_code_span "trailing backtick stays enclosed" 'trailing`' "$out"

out="$(md_code '`')"
assert_inert_code_span "a lone backtick stays enclosed" '`' "$out"

# --- the two seams together --------------------------------------------------
#
# sanitize runs at record time and md_code at render time. Neither re-runs the
# other, so the guarantee only holds if a detail that passes through both comes
# out inert AND still occupies exactly one table cell.

printf '\nrecord -> render: an adversarial detail end to end\n'
protects "sanitize and md_code defend different layers and run at different times; a detail is only safe if the composition is safe"

mapfile -t SCRUB < <(sentry_scrub_args)
hostile='::error::forged [link](https://attacker.example) <img src="https://attacker.example/b.png"> | col | col `tick`'
env "${SCRUB[@]}" \
  SENTRY_STATUS_FILE="${WORK}/status.tsv" \
  GITHUB_STEP_SUMMARY="${WORK}/summary.md" \
  bash "$STATUS_SCRIPT" record sourcemaps warn "$hostile" > "${WORK}/annotations.txt" 2>&1
env "${SCRUB[@]}" \
  SENTRY_STATUS_FILE="${WORK}/status.tsv" \
  GITHUB_STEP_SUMMARY="${WORK}/summary.md" \
  bash "$STATUS_SCRIPT" render sourcemaps > /dev/null 2>&1

annotations="$(cat "${WORK}/annotations.txt")"
summary="$(cat "${WORK}/summary.md")"

assert_line_count "the annotation is a single line" 1 "Sentry sourcemaps" "$annotations"
assert_not_contains "the annotation carries no forgeable ::" \
  "::error::forged" "$annotations"
assert_line_count "the detail occupies exactly one table row" \
  1 "| sourcemaps | **WARNING** |" "$summary"

row="$(printf '%s\n' "$summary" | grep -F '| sourcemaps | **WARNING** |')"
cell="${row#| sourcemaps | **WARNING** | }"
cell="${cell% |}"
assert_inert_code_span "the rendered cell is an inert code span" "$hostile" "$cell"
assert_contains "the operator can still read what happened" "attacker.example" "$cell"

finish
