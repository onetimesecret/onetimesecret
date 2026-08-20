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
#   sentry-status.sh render
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
sanitize() {
  printf '%s' "$*" | tr '\n\r\t' '   ' | sed 's/::/;;/g' | cut -c1-700
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

render() {
  local summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

  {
    echo ""
    echo "## Sentry delivery"
    echo ""
  } >> "$summary"

  if [ ! -s "$STATUS_FILE" ]; then
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
    # Escape pipes so a detail string cannot break the table layout.
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
        "${component//|/\\|}" "$label" "${detail//|/\\|}"
    done < "$STATUS_FILE"
    echo ""
  } >> "$summary"

  # Recap line: one place to look that answers "did telemetry actually ship?".
  local bad
  bad="$(awk -F'\t' '($2=="failed" || $2=="blocked" || $2=="warn") && !seen[$1]++ {print $1}' \
    "$STATUS_FILE" | paste -sd',' -)"
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
    render) render ;;
    *)
      echo "usage: $0 {record <component> <state> <detail...>|render}" >&2
      ;;
  esac
  return 0
}

main "$@"
exit 0
