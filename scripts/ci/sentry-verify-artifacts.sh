#!/usr/bin/env bash
#
# scripts/ci/sentry-verify-artifacts.sh
#
# POST-UPLOAD verification: ask Sentry whether the release that was just
# uploaded actually holds any artifacts.
#
# WHY THIS EXISTS
#
# This is the only check that would have caught the real bug. The pre-upload
# preflight asserts the inputs; `sentry-cli` reports its own exit code. Both
# were satisfiable while zero artifacts existed on the server — the upload ran
# against a directory that was not there, exited 0, and `continue-on-error`
# turned the whole thing green. The failure was invisible for months because
# nobody ever asked the receiving end.
#
# So we ask the receiving end. Three listings are checked, because a Sentry
# release can hold artifacts in more than one shape and only the union means
# "symbolication has something to work with":
#
#   1. organization release files  — classic per-release artifacts
#   2. project release files       — the same, scoped to the upload's project
#   3. project artifact bundles    — modern debug-id bundles
#
# Zero across all three, with credentials configured and an upload attempted,
# is reported as FAILED (::error:: + a row in the job summary). Anything that
# prevents an answer — token scope, network, an API shape we do not recognise —
# is reported as a warning and explicitly labelled UNVERIFIED, so "could not
# check" never gets mistaken for "checked and fine".
#
# NEVER exits non-zero.
#
# Environment:
#   SENTRY_AUTH_TOKEN   required; absence is a quiet skip
#   SENTRY_ORG          required
#   SENTRY_PROJECT      project the upload targeted (default: frontend)
#   SENTRY_RELEASE      release the upload tagged bundles with
#   SENTRY_URL          instance base URL (default: https://sentry.io)
#   VERIFY_ATTEMPTS     poll count before declaring zero (default 3)
#   VERIFY_DELAY        seconds between polls (default 5)
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATUS="${REPO_ROOT}/scripts/ci/sentry-status.sh"

ORG="${SENTRY_ORG:-}"
PROJECT="${SENTRY_PROJECT:-frontend}"
RELEASE="${SENTRY_RELEASE:-}"
BASE_URL="${SENTRY_URL:-https://sentry.io}"
BASE_URL="${BASE_URL%/}"
ATTEMPTS="${VERIFY_ATTEMPTS:-3}"
DELAY="${VERIFY_DELAY:-5}"

report() { bash "$STATUS" record "$@"; }

if [ -z "${SENTRY_AUTH_TOKEN:-}" ]; then
  report sourcemaps-verify skipped "SENTRY_AUTH_TOKEN not configured; nothing to verify"
  exit 0
fi

if [ -z "$ORG" ] || [ -z "$RELEASE" ]; then
  report sourcemaps-verify warn \
    "UNVERIFIED — SENTRY_ORG or SENTRY_RELEASE is empty, so the artifact count for this build could not be queried."
  exit 0
fi

if ! command -v jq > /dev/null 2>&1; then
  report sourcemaps-verify warn \
    "UNVERIFIED — jq is unavailable on this runner, so the Sentry artifact count could not be parsed."
  exit 0
fi

# Returns the element count of a JSON array endpoint, or -1 when the endpoint
# could not be read (HTTP error, or a body that is not a JSON array — e.g. an
# error object, which self-hosted returns for an unknown release).
count_endpoint() {
  local url="$1" body http_code
  body="$(curl -sS --max-time 30 -w $'\n%{http_code}' \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
    -H 'Accept: application/json' \
    "$url" 2>/dev/null)"
  http_code="$(printf '%s' "$body" | tail -n1)"
  body="$(printf '%s' "$body" | sed '$d')"

  case "$http_code" in
    200) ;;
    *) printf -- '-1'; return 0 ;;
  esac

  printf '%s' "$body" | jq -r 'if type == "array" then length else -1 end' 2>/dev/null \
    || printf -- '-1'
}

ORG_FILES_URL="${BASE_URL}/api/0/organizations/${ORG}/releases/${RELEASE}/files/"
PROJ_FILES_URL="${BASE_URL}/api/0/projects/${ORG}/${PROJECT}/releases/${RELEASE}/files/"
BUNDLES_URL="${BASE_URL}/api/0/projects/${ORG}/${PROJECT}/files/artifact-bundles/?query=${RELEASE}"

attempt=1
while :; do
  org_files="$(count_endpoint "$ORG_FILES_URL")"
  proj_files="$(count_endpoint "$PROJ_FILES_URL")"
  bundles="$(count_endpoint "$BUNDLES_URL")"

  total=0
  readable=0
  for n in "$org_files" "$proj_files" "$bundles"; do
    if [ "${n:-0}" -ge 0 ] 2>/dev/null; then
      readable=$((readable + 1))
      total=$((total + n))
    fi
  done

  echo "attempt ${attempt}/${ATTEMPTS}: org-release-files=${org_files} project-release-files=${proj_files} artifact-bundles=${bundles}"

  # Ingestion is not instant; a first look of zero is not yet proof of zero.
  if [ "$total" -gt 0 ] || [ "$readable" -eq 0 ] || [ "$attempt" -ge "$ATTEMPTS" ]; then
    break
  fi
  attempt=$((attempt + 1))
  sleep "$DELAY"
done

detail="release ${RELEASE}, project ${PROJECT} (org-release-files=${org_files}, project-release-files=${proj_files}, artifact-bundles=${bundles})"

if [ "$readable" -eq 0 ]; then
  report sourcemaps-verify warn \
    "UNVERIFIED — every artifact listing on ${BASE_URL} returned an error or an unexpected shape for ${detail}. Check that SENTRY_AUTH_TOKEN carries project:read, and that SENTRY_URL points at the instance the upload targeted."
  exit 0
fi

if [ "$total" -eq 0 ]; then
  report sourcemaps-verify failed \
    "ZERO artifacts on the server after a successful-looking upload — ${detail}. The upload reported success and shipped nothing; stack traces for this release will not symbolicate. This is the exact failure mode that hid for months, now caught at the source of truth."
  exit 0
fi

report sourcemaps-verify ok \
  "${total} artifact(s)/bundle(s) confirmed on ${BASE_URL} for ${detail}"
exit 0
