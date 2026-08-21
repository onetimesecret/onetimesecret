#!/usr/bin/env bash
#
# scripts/ci/sentry-status.sh
#
# Durable status reporter for the Sentry delivery steps of
# .github/workflows/build-and-publish-oci-images.yml.
#
# WHY THIS EXISTS
#
# Every Sentry step in that workflow carries `continue-on-error: true` so that
# telemetry plumbing can never fail a production image build. That is the right
# policy, but it makes the step's own exit code worthless as a signal: the job
# is green whether the sourcemaps shipped, silently uploaded zero files, or
# errored outright. This script is the replacement signal. It writes two things
# that survive the green check:
#
#   1. a GitHub annotation (::notice:: / ::warning:: / ::error::), which renders
#      on the run page and in the commit/PR checks UI;
#   2. a row in a collected status file that the final "Sentry delivery summary"
#      step renders into $GITHUB_STEP_SUMMARY.
#
# Annotation precedent: .github/workflows/validate-register.yml:141,145 and
# .github/workflows/compose-smoke.yml:205. Step-summary precedent: the "Output
# build summary" step in build-and-publish-oci-images.yml.
#
# USAGE
#
#   sentry-status.sh record <component> <state> <detail...>
#   sentry-status.sh render [expected-component ...]
#
# The components named on `render` are the ones the caller required for this
# event. Any of them with no row is reported as BLOCKED. A step that dies
# before it records — runner OOM mid `docker pull`, cancellation, a step
# timeout — leaves `continue-on-error` holding an empty output, every
# downstream `if:` false, and no row at all; without the assertion the recap
# then claims a clean run for work that never started. With no arguments
# `render` reports only what it finds, which is what the pull_request path
# wants.
#
# DETAIL STRINGS ARE PUBLISHED. This repository is public, so both the
# annotation and the job summary are world-readable, and GitHub redacts a
# secret only when the text matches the registered value exactly. A fragment
# of one — a prefix left by truncation, a substring left by escaping — is not
# masked and ships in the clear. Pass detail this repo authored. sentry-cli,
# docker and Sentry-server output is remote-controlled and belongs in the step
# log, where it is not summarised into a public artifact.
#
# STATES — the SKIPPED-vs-FAILED distinction is the entire point of this file.
# Before it, "no credentials on a fork" and "credentials present, upload
# errored" produced byte-identical output: a plain stdout line and a green
# check.
#
#   ok       work happened and succeeded                 -> ::notice::
#   skipped  no credentials configured. Expected on         (log line only —
#            forks, PRs and unconfigured clones; NOT a       deliberately no
#            defect, so it must not cry wolf                 annotation)
#   warn     something shipped, but a provable property   -> ::warning::
#            of the delivery is wrong
#   blocked  credentials ARE configured and a             -> ::warning::
#            precondition failed, so nothing shipped
#   failed   credentials ARE configured and the command   -> ::error::
#            errored
#
# This script never fails its caller: it always exits 0. Its job is to report,
# never to gate.
#
set -uo pipefail

STATUS_FILE="${SENTRY_STATUS_FILE:-${RUNNER_TEMP:-/tmp}/sentry-delivery-status.tsv}"

# Annotations are parsed out of the log stream, so any text interpolated into
# one must not be able to forge a workflow command or break out onto a new
# line. Detail strings here can carry sentry-cli output, which is external
# input. Same reasoning as validate-register.yml:135-143.
#
# The length cap cuts on whitespace, never mid-token. A character cut can land
# inside a URL, a DSN or a project slug that a caller interpolated, and the
# prefix it leaves no longer matches the value GitHub registered as a secret,
# so the runner cannot redact it and the fragment publishes. Dropping the
# straddling token whole keeps every value either fully present — and so
# maskable — or fully gone. A first token longer than the cap is dropped
# entirely for the same reason.
sanitize() {
  local text
  text="$(printf '%s' "$*" | tr '\n\r\t' '   ' | sed 's/::/;;/g')"

  if [ "${#text}" -gt 700 ]; then
    local head="${text:0:700}"
    case "$head" in
      *' '*) head="${head% *}" ;;
      *) head="" ;;
    esac
    text="${head} […truncated]"
  fi

  printf '%s' "$text"
}

record() {
  local component="${1:-unknown}"
  local state="${2:-warn}"
  shift 2 || true
  local detail
  detail="$(sanitize "${*:-}")"

  case "$state" in
    ok)
      echo "::notice::Sentry ${component}: OK — ${detail}"
      ;;
    skipped)
      # Info-level only, on purpose. A fork or an unconfigured clone hits this
      # path on every build; annotating it would train reviewers to ignore the
      # annotations that actually matter.
      echo "Sentry ${component}: SKIPPED — ${detail}"
      ;;
    warn)
      echo "::warning::Sentry ${component}: ${detail}"
      ;;
    blocked)
      echo "::warning::Sentry ${component} did NOT ship — ${detail}"
      ;;
    failed)
      echo "::error::Sentry ${component} FAILED — ${detail}"
      ;;
    *)
      state="warn"
      echo "::warning::Sentry ${component}: ${detail}"
      ;;
  esac

  mkdir -p "$(dirname "$STATUS_FILE")" 2>/dev/null
  printf '%s\t%s\t%s\n' "$component" "$state" "$detail" >> "$STATUS_FILE"
}

# The step summary is GFM; annotations are plain text and the status file is
# neither. Markup neutralisation therefore belongs here, at the render seam,
# next to the pipe escape that already lives here — the same detail stays
# legible in the log while the public summary gets an inert copy. Without it a
# remote-controlled detail can plant a live link or a Camo-proxied <img>
# beacon on this public repository's run page. A code span disarms links,
# images and the HTML subset in one move; its fence must outrun the longest
# backtick run it wraps, and content that starts or ends in a backtick needs a
# pad space (GFM 6.1).
md_code() {
  local text="${1:-}"
  local i ch run=0 longest=0 fence

  if [ -z "$text" ]; then
    printf '%s' "—"
    return 0
  fi

  for ((i = 0; i < ${#text}; i++)); do
    ch="${text:i:1}"
    if [ "$ch" = '`' ]; then
      run=$((run + 1))
      if [ "$run" -gt "$longest" ]; then longest="$run"; fi
    else
      run=0
    fi
  done

  printf -v fence '%*s' "$((longest + 1))" ''
  fence="${fence// /\`}"

  case "$text" in
    '`'*|*'`') text=" ${text} " ;;
  esac

  # Pipes stay escaped inside the span: GFM resolves table cell boundaries
  # before it parses inline spans, so a bare one still splits the row.
  printf '%s%s%s' "$fence" "${text//|/\\|}" "$fence"
}

render() {
  local summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
  local component missing=""
  local unreported="the step never reported a result, so delivery state is unknown and must be treated as not shipped"

  for component in "$@"; do
    [ -n "$component" ] || continue
    awk -F'\t' -v c="$component" '$1 == c { found = 1 } END { exit !found }' \
      "$STATUS_FILE" 2>/dev/null || missing="${missing}${component}"$'\n'
  done

  {
    echo ""
    echo "## Sentry delivery"
    echo ""
  } >> "$summary"

  # An empty status file is only benign when nothing was expected of it. With
  # expected components it means every one of them vanished, which the
  # assertion below has to say out loud rather than reassure about.
  if [ ! -s "$STATUS_FILE" ] && [ -z "$missing" ]; then
    {
      echo "No Sentry delivery steps ran for this event."
      echo ""
      echo "Expected for \`pull_request\` events; unexpected for tag, branch and"
      echo "nightly builds — if you see this on one of those, the Sentry steps"
      echo "were skipped by their \`if:\` conditions."
    } >> "$summary"
    return 0
  fi

  {
    echo "| Component | Result | Detail |"
    echo "| --- | --- | --- |"
    if [ -s "$STATUS_FILE" ]; then
      while IFS=$'\t' read -r component state detail; do
        [ -n "${component:-}" ] || continue
        local label
        case "$state" in
          ok) label="OK" ;;
          skipped) label="SKIPPED" ;;
          warn) label="WARNING" ;;
          blocked) label="BLOCKED" ;;
          failed) label="FAILED" ;;
          *) label="UNKNOWN" ;;
        esac
        printf '| %s | **%s** | %s |\n' \
          "${component//|/\\|}" "$label" "$(md_code "${detail:-}")"
      done < "$STATUS_FILE"
    fi
    while IFS= read -r component; do
      [ -n "$component" ] || continue
      printf '| %s | **BLOCKED** | %s |\n' \
        "${component//|/\\|}" "$(md_code "$unreported")"
    done <<< "$missing"
    echo ""
  } >> "$summary"

  while IFS= read -r component; do
    [ -n "$component" ] || continue
    echo "::warning::Sentry ${component} did NOT ship — ${unreported}"
  done <<< "$missing"

  # Recap line: one place to look that answers "did telemetry actually ship?".
  local bad
  bad="$( { awk -F'\t' '$2 == "failed" || $2 == "blocked" || $2 == "warn" { print $1 }' \
      "$STATUS_FILE" 2>/dev/null; printf '%s' "$missing"; } \
    | awk 'NF && !seen[$0]++ { print }' | paste -sd',' -)"
  if [ -n "$bad" ]; then
    {
      echo "> Sourcemap/release delivery is degraded for: ${bad}."
      echo "> The image build is unaffected (Sentry steps are non-blocking), but"
      echo "> stack traces for this release will be unsymbolicated or misfiled."
      echo ""
    } >> "$summary"
    echo "::warning::Sentry delivery degraded for: ${bad} (see the run's job summary)"
  else
    echo "> All Sentry delivery checks passed or were cleanly skipped." >> "$summary"
    echo "" >> "$summary"
  fi
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    record) record "$@" ;;
    render) render "$@" ;;
    *)
      echo "usage: $0 {record <component> <state> <detail...>|render [expected-component ...]}" >&2
      ;;
  esac
  return 0
}

main "$@"
exit 0
