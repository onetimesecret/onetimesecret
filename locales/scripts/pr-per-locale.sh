#!/usr/bin/env bash
#
# Open one pull request per i18n/update-<locale> branch, with a local `claude`
# translation-quality review baked into each PR body.
#
# Why a local review step (and why it's the throttle):
#   The review does double duty. It writes the quality summary that goes into the
#   PR body, AND — because each review is a real, locally-run `claude` invocation
#   that takes tens of seconds to a couple of minutes — it naturally paces the
#   loop. We make at most two `gh` API calls per branch (an existence check and
#   the create) spread out by the review time, instead of firing 26 PRs at the
#   GitHub API in a burst.
#
# One fresh agent per locale:
#   Each locale gets its OWN `claude` process, started from scratch with no shared
#   conversation or context from the other locales. Nothing leaks between reviews.
#
# The review agent reads locales/AGENT_TRANSLATION_PROTOCOL.md:
#   Each review is granted the Read tool and told to read that protocol first, so
#   it judges against the project's own translation rules rather than generic
#   instincts.
#
# Usage:
#   locales/scripts/pr-per-locale.sh [options] [locale...]
#
# Options:
#   --execute            Actually create PRs. Default is a dry run that prints
#                        the review + the exact `gh` command without calling it.
#   --base BRANCH        PR base branch (default: main).
#   --model MODEL        Model for the review agent (default: claude-sonnet-5).
#                        Use --model claude-opus-4-8 for a deeper review.
#   --agent-profile NAME Run each review as a named `claude` agent definition
#                        (passed through as `claude --agent NAME`), e.g. a
#                        translation-reviewer or code-reviewer agent from
#                        .claude/agents or a plugin. The agent supplies the
#                        reviewer persona/tools; this script still supplies the
#                        per-locale task prompt, the diff, and --model. Unset by
#                        default (inline review prompt only).
#   --no-review          Skip the claude review (PR body carries stats only).
#   --skip-validation    Skip the up-front variable-validation pass (Stage 0)
#                        that materializes each branch and writes per-locale
#                        i18n-validate-<locale>.json files. PR bodies then show
#                        "Variable validation not run" instead of a mismatch count.
#   --update             If an open PR already exists for the branch, refresh its
#                        body instead of skipping it.
#   --results-dir DIR    Where to write validation JSON + review artifacts
#                        (default: locales/reviews/<timestamp>).
#   --review-timeout SEC Per-locale review timeout (default: 300).
#   --sleep SEC          Extra sleep after each gh call (default: 0; the review
#                        is already the main throttle).
#   -h, --help           Show this help.
#
# Examples:
#   locales/scripts/pr-per-locale.sh                     # dry run, all locales
#   locales/scripts/pr-per-locale.sh de es fr_FR         # dry run, three locales
#   locales/scripts/pr-per-locale.sh --execute           # create all PRs
#   locales/scripts/pr-per-locale.sh --execute --model claude-opus-4-8 de
#
# Prerequisites (checked at startup): git, and — in --execute mode — an
# authenticated `gh` CLI. `claude` is required unless --no-review. `python3`+`jq`
# enable the variable-validation section; without them that section is skipped.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration / argument parsing
# ---------------------------------------------------------------------------
BASE_BRANCH=main
MODEL=claude-sonnet-5
AGENT_PROFILE=""
EXECUTE=false
DO_REVIEW=true
SKIP_VALIDATION=false
UPDATE_EXISTING=false
REVIEW_TIMEOUT=300
SLEEP_AFTER=0
RESULTS_DIR=""
PROTOCOL=locales/AGENT_TRANSLATION_PROTOCOL.md
BRANCH_PREFIX="i18n/update-"

die() { echo "error: $1" >&2; exit 1; }

REQUESTED_LOCALES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute)        EXECUTE=true ;;
    --base)           BASE_BRANCH="${2:?--base needs a branch}"; shift ;;
    --base=*)         BASE_BRANCH="${1#*=}" ;;
    --model)          MODEL="${2:?--model needs a value}"; shift ;;
    --model=*)        MODEL="${1#*=}" ;;
    --agent-profile)  AGENT_PROFILE="${2:?--agent-profile needs an agent name}"; shift ;;
    --agent-profile=*) AGENT_PROFILE="${1#*=}" ;;
    --no-review)      DO_REVIEW=false ;;
    --skip-validation) SKIP_VALIDATION=true ;;
    --update)         UPDATE_EXISTING=true ;;
    --results-dir)    RESULTS_DIR="${2:?--results-dir needs a path}"; shift ;;
    --results-dir=*)  RESULTS_DIR="${1#*=}" ;;
    --review-timeout) REVIEW_TIMEOUT="${2:?--review-timeout needs seconds}"; shift ;;
    --sleep)          SLEEP_AFTER="${2:?--sleep needs seconds}"; shift ;;
    -h|--help)
      # Print the leading comment block (skip shebang, stop at first blank/non-comment).
      awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
      exit 0 ;;
    --*) die "unknown option: $1 (see --help)" ;;
    *)   REQUESTED_LOCALES+=("$1") ;;
  esac
  shift
done

cd "$(git rev-parse --show-toplevel)" || die "not inside a git repository"

# Default results/review directory. `date` is only used for a human-facing
# directory name, so a fixed fallback keeps the script usable if date is odd.
if [[ -z "$RESULTS_DIR" ]]; then
  RESULTS_DIR="locales/reviews/$(date +%Y-%m-%d-%H%M 2>/dev/null || echo pr-run)"
fi
mkdir -p "$RESULTS_DIR"

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------
command -v git >/dev/null 2>&1 || die "git not found on PATH"

if $DO_REVIEW; then
  command -v claude >/dev/null 2>&1 || die "claude not found on PATH (use --no-review to skip the review step)"
  [[ -f "$PROTOCOL" ]] || echo "warning: $PROTOCOL not found; review agents will fall back to the diff alone" >&2
fi

if $EXECUTE; then
  command -v gh >/dev/null 2>&1 || die "gh CLI not found on PATH (required for --execute)"
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated; run 'gh auth login'"
fi

git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1 \
  || git rev-parse --verify "origin/$BASE_BRANCH" >/dev/null 2>&1 \
  || die "base branch '$BASE_BRANCH' not found locally or on origin"

# Prefer origin/<base> as the comparison point so a stale local base doesn't skew
# diffs; fall back to the local base if there is no remote-tracking ref.
if git rev-parse --verify "origin/$BASE_BRANCH" >/dev/null 2>&1; then
  BASE_REF="origin/$BASE_BRANCH"
else
  BASE_REF="$BASE_BRANCH"
fi

# jq + python3 gate the optional variable-validation section; --skip-validation
# turns it off explicitly regardless of tool availability.
HAVE_VALIDATION=false
if ! $SKIP_VALIDATION \
   && command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 \
   && [[ -f locales/scripts/review-locale-branches.sh ]]; then
  HAVE_VALIDATION=true
fi

# ---------------------------------------------------------------------------
# Enumerate i18n/update-* branches (local AND origin), dedup by locale,
# preferring a local branch over its remote ref. Sorted for stable output.
# ---------------------------------------------------------------------------
declare -A REF_FOR=()
while IFS= read -r ref; do
  [[ -n "$ref" ]] || continue
  locale="${ref##*${BRANCH_PREFIX}}"
  [[ -n "${REF_FOR[$locale]:-}" ]] || REF_FOR["$locale"]="$ref"
done < <(git for-each-ref --format='%(refname:short)' \
           "refs/heads/${BRANCH_PREFIX}*" "refs/remotes/origin/${BRANCH_PREFIX}*")

# Restrict to requested locales if any were passed positionally.
declare -a LOCALES=()
if [[ ${#REQUESTED_LOCALES[@]} -gt 0 ]]; then
  for loc in "${REQUESTED_LOCALES[@]}"; do
    if [[ -n "${REF_FOR[$loc]:-}" ]]; then
      LOCALES+=("$loc")
    else
      echo "warning: no ${BRANCH_PREFIX}${loc} branch found, skipping" >&2
    fi
  done
else
  mapfile -t LOCALES < <(printf '%s\n' "${!REF_FOR[@]}" | sort)
fi

[[ ${#LOCALES[@]} -gt 0 ]] || die "no ${BRANCH_PREFIX}* branches to process"

echo "Base branch : $BASE_BRANCH ($BASE_REF)"
echo "Locales     : ${LOCALES[*]}"
echo "Review      : $($DO_REVIEW && echo "claude ($MODEL${AGENT_PROFILE:+, agent=$AGENT_PROFILE}), reads $PROTOCOL" || echo "disabled")"
echo "Mode        : $($EXECUTE && echo EXECUTE || echo 'DRY RUN (no PRs created)')"
echo "Artifacts   : $RESULTS_DIR"
echo

# ---------------------------------------------------------------------------
# Stage 0: objective variable validation for every branch, in one pass.
# Reuses the checked-in review-locale-branches.sh, which materializes each
# branch in a throwaway worktree and validates that branch's content.
# ---------------------------------------------------------------------------
if $HAVE_VALIDATION; then
  echo "Running variable validation across branches (this can take a moment)..."
  bash locales/scripts/review-locale-branches.sh validate "$RESULTS_DIR" >/dev/null 2>&1 || \
    echo "warning: variable validation pass failed; PR bodies will omit that section" >&2
  echo
fi

# validation_count LOCALE -> echoes an integer mismatch count, or "" if unknown.
validation_count() {
  local locale="$1" file="$RESULTS_DIR/i18n-validate-$1.json"
  $HAVE_VALIDATION || { echo ""; return; }
  [[ -f "$file" ]] || { echo ""; return; }
  jq --arg l "$locale" '(.summary[$l] // (.summary | to_entries | map(.value) | add) // 0)' \
    "$file" 2>/dev/null || echo ""
}

# ---------------------------------------------------------------------------
# The review prompt. LOCALE is interpolated per call. The agent is told to read
# the protocol (it has the Read tool), then judge the diff supplied on stdin.
# ---------------------------------------------------------------------------
build_review_prompt() {
  local locale="$1"
  cat <<PROMPT
You are reviewing an automated translation update for the "$locale" locale before it becomes a pull request.

FIRST, read the file $PROTOCOL in this repository and treat its rules as authoritative for this review. If you cannot read it, say so in one line and review against the general rules below.

On stdin you are given:
  1. The output of the automated variable-consistency check (JSON, or a note that it was not run).
  2. The full git diff of this branch, limited to locales/content/$locale/.

The English strings are the reference. Judge ONLY what a maintainer needs to know before merging:
  - Placeholder/variable preservation: {var}, {0}, {{var}}, %{var}, %s/%d and <tag>...</tag> MUST match the English source. Missing, renamed, or extra variables are Critical.
  - Brand/product terms (e.g. "Onetime Secret") must not be translated or altered.
  - Empty or placeholder values where the source is non-empty.
  - Untranslated English left in place, obvious machine-translation artifacts, or encoding/mojibake issues.
  - Any script-specific concern relevant to $locale (RTL bidi/punctuation; CJK spacing/width; Slavic case in templates; Romance apostrophes/accents not escaped).

Do NOT fix anything and do NOT echo the diff back. Output GitHub-flavored markdown, at most ~250 words, using EXACTLY these sections and nothing before them:

**Verdict:** one of "✅ Looks good", "⚠️ Needs review", or "❌ Blockers" — followed by a short reason (max ~8 words).

**Summary:** 1-2 sentences.

**Critical (must fix):** bullet list, or "None".

**Warnings:** bullet list, or "None".

**Notes:** bullet list, or "None".
PROMPT
}

# ---------------------------------------------------------------------------
# Per-locale processing. Invoked inside an `if` so a failure in one locale does
# not abort the whole run; outcomes are tallied for the final summary.
# ---------------------------------------------------------------------------
CREATED=(); UPDATED=(); SKIPPED=(); FAILED=()

process_locale() {
  local locale="$1"
  local head_ref="${REF_FOR[$locale]}"
  local branch="${BRANCH_PREFIX}${locale}"
  local locale_dir="locales/content/$locale"

  echo "──────────────────────────────────────────────────────────────"
  echo "[$locale] branch: $branch  (head ref: $head_ref)"

  # The PR head must exist on origin. If only a local branch exists, push it
  # (execute mode) or flag it (dry run).
  if ! git rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
    if $EXECUTE; then
      echo "[$locale] origin/$branch missing; pushing local branch..."
      git push -u origin "$branch" >/dev/null 2>&1 || { echo "[$locale] push failed"; return 1; }
    else
      echo "[$locale] note: origin/$branch not found; --execute would push it first"
    fi
  fi

  # Nothing to PR if the branch introduces no changes under its locale dir.
  if git diff --quiet "$BASE_REF"..."$head_ref" -- "$locale_dir/" 2>/dev/null; then
    echo "[$locale] no changes vs $BASE_BRANCH under $locale_dir — skipping"
    SKIPPED+=("$locale (no changes)")
    return 0
  fi

  # Existing-PR check (one lightweight gh call). Only in execute mode; a dry run
  # should not depend on gh being present.
  local existing_url="" existing_num=""
  if $EXECUTE; then
    local pr_json
    pr_json="$(gh pr list --base "$BASE_BRANCH" --head "$branch" --state open \
                 --json number,url 2>/dev/null || echo '[]')"
    existing_num="$(jq -r '.[0].number // empty' <<<"$pr_json" 2>/dev/null || true)"
    existing_url="$(jq -r '.[0].url // empty' <<<"$pr_json" 2>/dev/null || true)"
    if [[ -n "$existing_num" ]] && ! $UPDATE_EXISTING; then
      echo "[$locale] open PR already exists: $existing_url — skipping (use --update to refresh)"
      SKIPPED+=("$locale (PR #$existing_num exists)")
      return 0
    fi
  fi

  # Stats + potential-conflict hint.
  local shortstat files ins del mergebase base_touched=""
  shortstat="$(git diff --shortstat "$BASE_REF"..."$head_ref" -- "$locale_dir/" 2>/dev/null || true)"
  files="$(git diff --name-only "$BASE_REF"..."$head_ref" -- "$locale_dir/" 2>/dev/null | wc -l | tr -d ' ')"
  ins="$(grep -oE '([0-9]+) insertion' <<<"$shortstat" | grep -oE '[0-9]+' || echo 0)"
  del="$(grep -oE '([0-9]+) deletion' <<<"$shortstat" | grep -oE '[0-9]+' || echo 0)"
  mergebase="$(git merge-base "$BASE_REF" "$head_ref" 2>/dev/null || true)"
  if [[ -n "$mergebase" ]] && ! git diff --quiet "$mergebase" "$BASE_REF" -- "$locale_dir/" 2>/dev/null; then
    base_touched="yes"
  fi

  # Variable-validation summary line.
  local vcount vline
  vcount="$(validation_count "$locale")"
  if [[ -z "$vcount" ]]; then
    vline="ℹ️ Variable validation not run."
  elif [[ "$vcount" == "0" ]]; then
    vline="✅ \`i18n validate variables\`: no variable mismatches."
  else
    vline="⚠️ \`i18n validate variables\` reports **$vcount** variable mismatch(es) for \`$locale\` (empty values that drop source variables, renamed/extra vars, etc.) — see the review below."
  fi

  # Assemble the review context (validation JSON + diff) once; reused for the
  # review stdin and, on failure, discarded.
  local ctx diff_file review_file
  ctx="$(mktemp)"; diff_file="$(mktemp)"
  review_file="$RESULTS_DIR/$locale.md"
  git diff "$BASE_REF"..."$head_ref" -- "$locale_dir/" >"$diff_file" 2>/dev/null || true

  {
    echo "===== VARIABLE VALIDATION (JSON) ====="
    if $HAVE_VALIDATION && [[ -f "$RESULTS_DIR/i18n-validate-$locale.json" ]]; then
      cat "$RESULTS_DIR/i18n-validate-$locale.json"
    else
      echo "Not run."
    fi
    echo
    echo "===== GIT DIFF ($locale_dir) ====="
    # Cap the diff so a huge export can't blow up the context window.
    head -c 400000 "$diff_file"
    [[ "$(wc -c <"$diff_file")" -gt 400000 ]] && echo $'\n[diff truncated at 400 KB for review]'
  } >"$ctx"

  # ---- The fresh, isolated review agent for THIS locale -------------------
  local review_md=""
  if $DO_REVIEW; then
    echo "[$locale] running fresh claude review ($MODEL${AGENT_PROFILE:+, agent=$AGENT_PROFILE})..."
    local raw rc=0
    # Capture claude's stderr and raw stdout to per-locale files. stderr is the
    # only place API errors (rate-limit, auth, overload) surface; discarding it
    # is what makes a failed review undiagnosable. The raw stdout is persisted
    # unconditionally so a review is never lost to a transient/format hiccup.
    local stderr_file="$RESULTS_DIR/$locale.stderr" raw_file="$RESULTS_DIR/$locale.raw.txt"
    # Optional named agent profile -> `claude --agent NAME`. Expanded with the
    # ${arr[@]+"${arr[@]}"} guard so an unset profile adds no argument even under
    # `set -u`.
    local -a agent_args=()
    [[ -n "$AGENT_PROFILE" ]] && agent_args=(--agent "$AGENT_PROFILE")
    raw="$(timeout "$REVIEW_TIMEOUT" claude -p "$(build_review_prompt "$locale")" \
             --model "$MODEL" \
             ${agent_args[@]+"${agent_args[@]}"} \
             --allowedTools "Read" \
             --output-format text <"$ctx" 2>"$stderr_file")" || rc=$?
    printf '%s' "$raw" >"$raw_file"
    if [[ $rc -ne 0 || -z "$raw" ]]; then
      echo "[$locale] review did not complete (exit $rc); see $stderr_file"
      review_md="_Automated review did not complete (exit $rc). See \`$stderr_file\` for the error and \`$raw_file\` for any partial output._"
    else
      # Strip any agent preamble/reasoning that leaked ahead of the structured
      # review (some agent profiles emit a "thinking out loud" line first). The
      # prompt mandates the output begin with "**Verdict:**", so drop everything
      # before the first line containing that marker. If the marker is absent
      # (unexpected format), keep the raw output untouched.
      if grep -q '\*\*Verdict:\*\*' <<<"$raw"; then
        review_md="$(awk 'seen || /\*\*Verdict:\*\*/ { seen=1; print }' <<<"$raw")"
      else
        review_md="$raw"
      fi
    fi
    # Drop an empty stderr file so a clean run leaves no noise behind.
    [[ -s "$stderr_file" ]] || rm -f "$stderr_file"
    # Persist the review artifact (matches locales/reviews/<date>/<locale>.md).
    { echo "# $locale review — $(basename "$RESULTS_DIR")"; echo; echo "$review_md"; } >"$review_file"
  else
    review_md="_Review step skipped (--no-review)._"
  fi

  # ---- Assemble the PR body ----------------------------------------------
  local body_file title
  body_file="$(mktemp)"
  title="i18n: update $locale translations"
  {
    echo "## \`$locale\` translation update"
    echo
    echo "Automated export of completed **$locale** translations from the translation task DB."
    echo "Scope: \`$locale_dir/\` only — ${files} file(s), +${ins}/-${del}."
    echo
    echo "$vline"
    if [[ -n "$base_touched" ]]; then
      echo
      echo "> ⚠️ \`$BASE_BRANCH\` has also modified \`$locale_dir/\` since this branch was cut — it may need a rebase/merge before it is conflict-free."
    fi
    echo
    echo "---"
    echo
    echo "### Local quality review"
    echo
    if $DO_REVIEW; then
      echo "> Produced by a fresh, isolated \`claude\` review agent (model \`$MODEL\`${AGENT_PROFILE:+, agent \`$AGENT_PROFILE\`}) that read"
      echo "> \`$PROTOCOL\` and inspected this branch's diff before the PR was opened."
      echo
    fi
    echo "$review_md"
    echo
    echo "---"
    echo "🤖 Generated with [Claude Code](https://claude.com/claude-code)"
  } >"$body_file"

  # ---- Create / update / preview -----------------------------------------
  if ! $EXECUTE; then
    echo "[$locale] DRY RUN — would run:"
    if [[ -n "$existing_num" ]]; then
      echo "  gh pr edit $existing_num --body-file <body>"
    else
      echo "  gh pr create --base $BASE_BRANCH --head $branch --title \"$title\" --body-file <body>"
    fi
    echo "[$locale] ----- PR body preview -----"
    sed 's/^/    /' "$body_file"
    echo "[$locale] ---------------------------"
    SKIPPED+=("$locale (dry run)")
  elif [[ -n "$existing_num" ]]; then
    if gh pr edit "$existing_num" --title "$title" --body-file "$body_file" >/dev/null 2>&1; then
      echo "[$locale] updated PR #$existing_num: $existing_url"
      UPDATED+=("$locale -> #$existing_num")
    else
      echo "[$locale] failed to update PR #$existing_num"
      FAILED+=("$locale (update failed)")
      rm -f "$ctx" "$diff_file" "$body_file"; return 1
    fi
  else
    local url
    if url="$(gh pr create --base "$BASE_BRANCH" --head "$branch" \
                --title "$title" --body-file "$body_file" 2>&1)"; then
      echo "[$locale] created PR: $url"
      CREATED+=("$locale -> $url")
    else
      echo "[$locale] gh pr create failed: $url"
      FAILED+=("$locale (create failed)")
      rm -f "$ctx" "$diff_file" "$body_file"; return 1
    fi
  fi

  rm -f "$ctx" "$diff_file" "$body_file"
  [[ "$SLEEP_AFTER" == "0" ]] || sleep "$SLEEP_AFTER"
  return 0
}

# ---------------------------------------------------------------------------
# Main loop — one locale at a time (sequential is the throttle).
# ---------------------------------------------------------------------------
for locale in "${LOCALES[@]}"; do
  if ! process_locale "$locale"; then
    echo "[$locale] processing errored; continuing"
  fi
  echo
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "════════════════════════════════ SUMMARY ════════════════════════════════"
printf 'Created : %s\n' "${#CREATED[@]}"; for x in "${CREATED[@]:-}"; do [[ -n "$x" ]] && echo "  + $x"; done
printf 'Updated : %s\n' "${#UPDATED[@]}"; for x in "${UPDATED[@]:-}"; do [[ -n "$x" ]] && echo "  ~ $x"; done
printf 'Skipped : %s\n' "${#SKIPPED[@]}"; for x in "${SKIPPED[@]:-}"; do [[ -n "$x" ]] && echo "  - $x"; done
printf 'Failed  : %s\n' "${#FAILED[@]}";  for x in "${FAILED[@]:-}";  do [[ -n "$x" ]] && echo "  ! $x"; done
echo
echo "Review artifacts: $RESULTS_DIR"
$EXECUTE || echo "This was a DRY RUN. Re-run with --execute to open the PRs."
