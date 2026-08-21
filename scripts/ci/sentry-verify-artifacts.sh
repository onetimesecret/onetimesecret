#!/usr/bin/env bash
#
# scripts/ci/sentry-verify-artifacts.sh
#
# POST-UPLOAD verification: ask Sentry whether the release that was just
# uploaded actually holds artifacts symbolication can resolve.
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
# So we ask the receiving end, with the query symbolication itself runs:
#
#   1. artifact-lookup ?release=&dist=  — AUTHORITATIVE. Sentry resolves a
#      bundle for an event only when release AND dist BOTH match; this endpoint
#      filters on both together, and is the one Symbolicator asks. A non-empty
#      answer means "symbolication would find this", not merely "a row exists".
#   2. project artifact bundles ?query= — SECONDARY, release-only. Its filter is
#      exact, but a DISJUNCTION (release_name OR dist_name), so it can never
#      confirm the join. It is kept to tell two zeros apart: bundles present for
#      the release while the lookup resolves none means the dist does not match,
#      which is the actionable diagnosis and the exact shape of the bug this
#      pipeline shipped for months.
#
# The classic release-file listings are NOT consulted for the verdict, and this
# is the trap that made them worse than useless: sentry-cli 3.x uploads only
# artifact bundles (SourceFilesUploader::upload -> upload_files_chunked ->
# assemble_artifact_bundle), and the server's assemble task writes ArtifactBundle
# rows and never a ReleaseFile, so both listings answer 200-with-[] after a
# perfectly good upload. Counting those 200s as "readable" made an unreadable
# bundle probe indistinguishable from a genuine zero and would report FAILED
# saying "nothing shipped" when the truth was "the only endpoint carrying the
# answer could not be read". They are now probed once, only when the verdict is
# already negative, and mentioned only when non-empty — a non-zero there means
# something used the pre-bundle upload path, which resolves differently.
#
# Anything that prevents an answer — token scope, network, an API shape we do
# not recognise — is reported as a warning and explicitly labelled UNVERIFIED,
# so "could not check" never gets mistaken for "checked and fine". Every such
# report names the probe that failed and the HTTP status it got, because an
# UNVERIFIED that cannot be told apart from another UNVERIFIED is the same
# silent failure in a different coat.
#
# ENDPOINT STABILITY: both endpoints are `publish_status = PRIVATE`. They are
# in-product endpoints the Sentry UI and Symbolicator depend on, not deprecated
# ones, but they are absent from the public API reference and carry no
# cross-version compatibility guarantee. Shapes here were read off
# getsentry/sentry at tag 26.3.1, the version this instance runs. An upgrade may
# change them with no deprecation notice; UNVERIFIED is the designed outcome
# when it does, and re-reading the source is the way to re-confirm.
#
# NEVER exits non-zero.
#
# Environment:
#   SENTRY_AUTH_TOKEN   required; absence is a quiet skip
#   SENTRY_ORG          required
#   SENTRY_PROJECT      project the upload targeted (default: frontend)
#   SENTRY_RELEASE      release the upload tagged bundles with
#   SENTRY_DIST         dist the upload tagged bundles with; absence downgrades
#                       the verdict, it does not relax it (see below)
#   SENTRY_URL          instance base URL (default: https://sentry.io)
#   VERIFY_ATTEMPTS     poll count before declaring zero (default 3)
#   VERIFY_DELAY        seconds between polls (default 5)
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATUS="${REPO_ROOT}/scripts/ci/sentry-status.sh"

ORG="${SENTRY_ORG:-}"
# Builds URLs, is never reported — same rule the workflow applies to its own ten
# call sites. It arrives from a secret on this repo, and while an intact value
# does render masked, `sanitize()` truncates a long detail at 700 characters and
# can cut a straddling secret at a whitespace boundary, leaving an unmasked
# prefix in a world-readable annotation. A row saying `***` would tell an
# operator nothing anyway; the release, the dist and the counts do.
PROJECT="${SENTRY_PROJECT:-frontend}"
RELEASE="${SENTRY_RELEASE:-}"
DIST="${SENTRY_DIST:-}"
BASE_URL="${SENTRY_URL:-https://sentry.io}"
# Build URLs with this, never report it. GitHub masks a secret by exact value
# only, so a slash-stripped SENTRY_URL is a proper prefix that no longer
# matches the mask and would publish a self-hosted hostname in the clear —
# annotations and the job summary are world-readable on a public repo.
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

# Emits "<count> <status>": the element count of a JSON array endpoint, or -1
# when the endpoint could not be read (HTTP error, transport failure, or a body
# that is not a JSON array — e.g. an error object, which self-hosted returns for
# an unknown release).
#
# The status is carried out alongside the count because an UNVERIFIED with no
# code attached is indistinguishable from itself: 401 (token rejected), 403
# (token lacks project:read), 404 (wrong org, project or instance) and a connect
# timeout each want a different operator action, and this script exists to end
# exactly that kind of silent ambiguity. A three-digit code and a curl exit code
# are values we produce, not remote-controlled text — the response BODY is, and
# it never leaves this function.
count_endpoint() {
  local url="$1" body http_code rc count
  # The token is fed over a pipe rather than argv: an argument is visible in
  # /proc/<pid>/cmdline to any same-user process for the life of the request,
  # and --config - leaves no temp file to guard or clean up.
  body="$(printf 'header = "Authorization: Bearer %s"\n' "${SENTRY_AUTH_TOKEN}" \
    | curl -sS --max-time 30 -w $'\n%{http_code}' \
      --config - \
      -H 'Accept: application/json' \
      "$url" 2>/dev/null)"
  rc=$?
  http_code="$(printf '%s' "$body" | tail -n1)"
  body="$(printf '%s' "$body" | sed '$d')"

  # curl exited non-zero: no HTTP exchange completed, so %{http_code} is 000 and
  # the exit code is the only evidence there is (6 DNS, 7 refused, 28 timed out,
  # 35/60 TLS). Reported apart from an HTTP code because "the instance answered
  # and said no" and "nothing answered" are different faults.
  if [ "$rc" -ne 0 ]; then
    printf -- '-1 curl-%s' "$rc"
    return 0
  fi

  case "$http_code" in
    200) ;;
    *) printf -- '-1 %s' "${http_code:-000}"; return 0 ;;
  esac

  count="$(printf '%s' "$body" | jq -r 'if type == "array" then length else -1 end' 2>/dev/null)"
  printf -- '%s %s' "${count:--1}" "$http_code"
}

# A -1 paired with 200 means the endpoint answered but not with a JSON array,
# which is the API-shape drift a version upgrade would cause; it reads
# differently from a refusal and must not be collapsed into one.
status_phrase() {
  case "$1" in
    curl-*) printf 'nothing at all — no HTTP response, curl exit %s' "${1#curl-}" ;;
    200) printf 'HTTP 200 with a body that is not a JSON array' ;;
    *) printf 'HTTP %s' "$1" ;;
  esac
}

# The join keys reach both a path segment and a query value. A release name
# carrying '+', '/', '#' or a space would otherwise query something other than
# what was uploaded and answer confidently about it — the same quiet wrong
# answer this script exists to catch.
urlenc() { jq -rn --arg v "$1" '$v | @uri'; }

RELEASE_ENC="$(urlenc "$RELEASE")"
DIST_ENC="$(urlenc "$DIST")"

# `url=` is a substring match over the bundle file index, and it is purely
# additive: below the server's indexing threshold (3 bundles for this
# release+dist) the endpoint answers from the release query and this matches
# nothing extra, at or above it the release query is SKIPPED and this is the
# only clause that can match. Without it, the fourth re-run of one commit would
# report zero while every bundle was present and resolvable.
LOOKUP_URL="${BASE_URL}/api/0/projects/${ORG}/${PROJECT}/artifact-lookup/?release=${RELEASE_ENC}&dist=${DIST_ENC}&url=.js"
BUNDLES_URL="${BASE_URL}/api/0/projects/${ORG}/${PROJECT}/files/artifact-bundles/?query=${RELEASE_ENC}"
ORG_FILES_URL="${BASE_URL}/api/0/organizations/${ORG}/releases/${RELEASE_ENC}/files/"
PROJ_FILES_URL="${BASE_URL}/api/0/projects/${ORG}/${PROJECT}/releases/${RELEASE_ENC}/files/"

# Deferred to the negative paths only: these read ReleaseFile rows a bundle
# upload never writes, so their zero carries no information and reporting it on
# every run would train a reader to skim past a row that does.
LEGACY_NOTE=""
probe_legacy() {
  local org_files proj_files org_status proj_status
  read -r org_files org_status <<< "$(count_endpoint "$ORG_FILES_URL")"
  read -r proj_files proj_status <<< "$(count_endpoint "$PROJ_FILES_URL")"
  echo "legacy release-file listings: org=${org_files} (${org_status}) project=${proj_files} (${proj_status})"
  if [ "${org_files:-0}" -gt 0 ] 2>/dev/null || [ "${proj_files:-0}" -gt 0 ] 2>/dev/null; then
    LEGACY_NOTE=" The legacy release-file listings are NOT empty (org=${org_files}, project=${proj_files}), so something is still uploading through the pre-bundle path."
  fi
}

attempt=1
while :; do
  read -r bundles bundles_status <<< "$(count_endpoint "$BUNDLES_URL")"
  bundles="${bundles:-0}"
  if [ -n "$DIST" ]; then
    read -r lookup lookup_status <<< "$(count_endpoint "$LOOKUP_URL")"
    lookup="${lookup:-0}"
    found="$lookup"
    lookup_label="${lookup} (${lookup_status})"
  else
    lookup=-1
    lookup_status="not-probed"
    found="$bundles"
    lookup_label="not-probed (SENTRY_DIST unset)"
  fi

  # Status codes go in the step log at every attempt, not only in the verdict:
  # a probe that answers 403 twice and a probe that answers 502 then 200 are the
  # same verdict and different problems.
  echo "attempt ${attempt}/${ATTEMPTS}: symbolication-lookup=${lookup_label} release-bundles=${bundles} (${bundles_status})"

  # Ingestion is not instant; a first look of zero is not yet proof of zero. A
  # -1 breaks out with the zeros: an unreadable endpoint is a scope or routing
  # problem, and re-asking it only spends the delay budget to fail identically.
  if [ "$found" -ne 0 ] 2>/dev/null || [ "$attempt" -ge "$ATTEMPTS" ]; then
    break
  fi
  attempt=$((attempt + 1))
  sleep "$DELAY"
done

if [ -z "$DIST" ]; then
  target="release ${RELEASE}"

  if [ "$bundles" -lt 0 ] 2>/dev/null; then
    report sourcemaps-verify warn \
      "UNVERIFIED — the artifact bundle listing for ${target} answered $(status_phrase "$bundles_status"), so the server was never successfully asked. 401/403: SENTRY_AUTH_TOKEN lacks project:read. 404: the org or project slug does not exist on the instance SENTRY_URL names. No response: the runner could not reach that instance."
    exit 0
  fi

  if [ "$bundles" -eq 0 ]; then
    probe_legacy
    report sourcemaps-verify failed \
      "ZERO artifact bundles on the server after a successful-looking upload — ${target}. The upload reported success and shipped nothing; stack traces for this release will not symbolicate. This is the exact failure mode that hid for months, now caught at the source of truth.${LEGACY_NOTE}"
    exit 0
  fi

  # Half the join key is unverifiable, so this cannot be reported as OK. Asking
  # the lookup endpoint without a dist would NOT mean "any dist": a missing dist
  # parameter is mapped to the empty string and matched exactly, so it asserts
  # that the upload passed no --dist — the opposite of what this pipeline does.
  report sourcemaps-verify warn \
    "UNVERIFIED on the dist half — bundle(s) exist for ${target}, but SENTRY_DIST was not passed to this step, so the release+dist join that symbolication requires was never checked. Pass this step the same dist the upload used."
  exit 0
fi

target="release ${RELEASE}, dist ${DIST}"

if [ "$lookup" -lt 0 ] 2>/dev/null; then
  report sourcemaps-verify warn \
    "UNVERIFIED — the artifact-lookup probe for ${target} answered $(status_phrase "$lookup_status"), so whether symbolication can resolve this release is unknown. 401/403: SENTRY_AUTH_TOKEN lacks project:read. 404: the org or project slug does not exist on the instance SENTRY_URL names. No response: the runner could not reach that instance."
  exit 0
fi

if [ "$lookup" -eq 0 ] && [ "$bundles" -gt 0 ] 2>/dev/null; then
  probe_legacy
  report sourcemaps-verify failed \
    "DIST MISMATCH — ${bundles} artifact bundle(s) exist for ${target}, but none of them join on that dist, so symbolication resolves nothing for events carrying it. The upload landed; it landed under a different dist (or none). Make the upload's --dist and the frontend's Sentry.init dist the same string.${LEGACY_NOTE}"
  exit 0
fi

if [ "$lookup" -eq 0 ]; then
  probe_legacy
  # bundles == -1 here means the release-only cross-check was unreadable, so
  # "nothing shipped" and "shipped under another dist" cannot be told apart.
  cross_check=""
  if [ "$bundles" -lt 0 ] 2>/dev/null; then
    cross_check=" The release-only cross-check answered $(status_phrase "$bundles_status"), so a dist mismatch cannot be ruled out."
  fi
  report sourcemaps-verify failed \
    "ZERO resolvable artifacts on the server after a successful-looking upload — ${target}. The upload reported success and shipped nothing symbolication can find; stack traces for this release will not symbolicate. This is the exact failure mode that hid for months, now caught at the source of truth.${cross_check}${LEGACY_NOTE}"
  exit 0
fi

# Reported as existence, not as a total: both probes cap their page size (the
# lookup at the server's per-query bundle limit, the listing at 10), so the
# number understates a large upload and must not be read as an artifact count.
report sourcemaps-verify ok \
  "symbolication can resolve ${target} — the artifact-lookup probe, the same release+dist query Sentry runs for an event, returns ${lookup} bundle(s). Page sizes are capped server-side, so this confirms existence rather than a count."
exit 0
