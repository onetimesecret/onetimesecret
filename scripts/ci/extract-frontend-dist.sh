#!/usr/bin/env bash
#
# scripts/ci/extract-frontend-dist.sh
#
# Materialise the built frontend tree (public/web/dist) on the runner so the
# Sentry sourcemap upload has something to upload.
#
# WHY THIS EXISTS
#
# The sourcemap step has never shipped a single artifact. Confirmed against the
# self-hosted Sentry: every release (b7aaea0, a3c5ebf, 03277fa, 58df007,
# b8efb81 ...) has zero release files and the frontend project has zero
# artifact bundles, ever. The cause is structural, not transient:
#
#   * the frontend is compiled INSIDE the OCI image — Dockerfile stage `build`
#     runs `pnpm run build`, and vite writes ${APP_DIR}/public/web/dist
#     (vite.config.ts: root './src', build.outDir '../public/web/dist');
#   * public/web/dist is gitignored, so on the runner it simply does not exist;
#   * `sentry-cli sourcemaps upload ./public/web/dist` against a missing
#     directory plus `continue-on-error: true` produced a green check and no
#     artifacts, on every build, for months.
#
# The fix has to take the assets from the image, not rebuild them. A runner-side
# `pnpm run build` would be a DIFFERENT build: vite emits content-hashed
# filenames (assets/[name].[hash].js), Sentry resolves classic release artifacts
# by URL, and sentry-cli's debug-id injection only rewrites the copy it is
# handed — never the copy inside the image that browsers actually load. Any
# toolchain drift between runner and image would yield artifacts named for files
# no browser will ever request: green again, useless again. So: pull the image
# that was just pushed and copy the exact tree out of it.
#
# NEVER exits non-zero. It reports through scripts/ci/sentry-status.sh and
# writes `status=` to $GITHUB_OUTPUT:
#
#   status=skipped    no SENTRY_AUTH_TOKEN — quiet, expected on forks/clones
#   status=blocked    credentials present, extraction impossible — loud
#   status=extracted  the tree is on disk at $DIST_DEST
#
# Environment:
#   SENTRY_AUTH_TOKEN  presence separates a quiet SKIP from a loud failure
#   DIST_DEST          where to place the tree (default ./public/web/dist)
#   IMAGE_DIST_PATH    path inside the image (default /app/public/web/dist)
#   BAKE_METADATA_FILE path to docker/bake-action `metadata` output (JSON),
#                      written to disk by the calling step rather than passed
#                      as an env var — group `ci` builds 3 targets x 2
#                      platforms and buildx attaches provenance/attestation
#                      data by default, so this JSON can run into the
#                      multi-MB range: large enough to blow the OS execve()
#                      argv+envp limit if it rode through `env:` instead (see
#                      docker/build-push-action#1257). When it carries a
#                      digest the pull is digest-pinned, which is immune to a
#                      tag being overwritten between push and pull.
#   BAKE_FILE          bake definition (default docker/bake.hcl)
#   BAKE_GROUP         bake group to resolve tags from (default ci)
#   BAKE_TARGET        target within that group to extract from (default main)
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATUS="${REPO_ROOT}/scripts/ci/sentry-status.sh"

DIST_DEST="${DIST_DEST:-${REPO_ROOT}/public/web/dist}"
IMAGE_DIST_PATH="${IMAGE_DIST_PATH:-/app/public/web/dist}"
BAKE_FILE="${BAKE_FILE:-docker/bake.hcl}"
BAKE_GROUP="${BAKE_GROUP:-ci}"
BAKE_TARGET="${BAKE_TARGET:-main}"

report() { bash "$STATUS" record "$@"; }

emit_status() {
  echo "status=${1}" >> "${GITHUB_OUTPUT:-/dev/null}"
  echo "frontend asset extraction: ${1}"
}

# Docker's output carries registry text, which a remote controls. The runner
# parses workflow commands off any log line whose first non-space character
# starts "::" (ActionCommand.TryParseV2 does TrimStart() before matching), so
# unprefixed remote text can forge an annotation or run ::add-mask:: /
# ::stop-commands::. A prefix at column one leaves the output whole and inert;
# indenting would not, because of that TrimStart.
log_docker_output() {
  [ -n "${1:-}" ] || return 0
  printf '%s\n' "$1" | sed 's/^/docker: /'
}

# Same rule as everywhere else in this pipeline: no credentials means nobody
# configured Sentry here, which is the normal state of a fork. Stay quiet.
if [ -z "${SENTRY_AUTH_TOKEN:-}" ]; then
  report frontend-assets skipped \
    "SENTRY_AUTH_TOKEN not configured; frontend assets not extracted (nothing would consume them)"
  emit_status skipped
  exit 0
fi

# --- resolve the image reference --------------------------------------------
#
# The tag set is computed by the tags() function in docker/bake.hcl from
# REGISTRY_MODE / IMAGE_TAG / EXTRA_TAGS. Re-deriving that in YAML would be a
# second copy of the logic, free to drift. Ask bake what it resolved instead —
# the same `--print` the "Audit — resolved bake configuration" step already runs.
IMAGE_REF=""
if command -v jq > /dev/null 2>&1; then
  IMAGE_REF="$(docker buildx bake -f "$BAKE_FILE" --print "$BAKE_GROUP" 2>/dev/null \
    | jq -r --arg t "$BAKE_TARGET" '.target[$t].tags[0] // empty' 2>/dev/null)"
else
  report frontend-assets blocked \
    "jq is unavailable on this runner, so the built image tag cannot be resolved from ${BAKE_FILE} --print; no assets extracted and no sourcemaps can be uploaded."
  emit_status blocked
  exit 0
fi

if [ -z "$IMAGE_REF" ]; then
  report frontend-assets blocked \
    "could not resolve a tag for bake target '${BAKE_TARGET}' in group '${BAKE_GROUP}' from ${BAKE_FILE} --print — the tag set is empty, which means IMAGE_TAG and EXTRA_TAGS were both empty for this event (see the tags() function in ${BAKE_FILE} and the 'Compute version and tags' step). No image to extract from, so no sourcemaps will ship."
  emit_status blocked
  exit 0
fi

# Prefer the digest the push actually produced. Tags are mutable; a digest names
# the exact image whose bundles this release's events will come from.
digest=""
if [ -n "${BAKE_METADATA_FILE:-}" ] && [ -s "$BAKE_METADATA_FILE" ]; then
  digest="$(jq -r --arg t "$BAKE_TARGET" '.[$t]["containerimage.digest"] // empty' \
    "$BAKE_METADATA_FILE" 2>/dev/null)"
fi

if [ -n "$digest" ]; then
  # Strip the tag, not a registry port: only the trailing ":..." that carries
  # no "/" is a tag (ghcr.io/x/y:tag vs registry.example:5000/x/y).
  IMAGE_REPO="$IMAGE_REF"
  case "${IMAGE_REF##*:}" in
    */*) : ;;                       # ":5000/x/y" — no tag present
    *)   IMAGE_REPO="${IMAGE_REF%:*}" ;;
  esac
  IMAGE_REF="${IMAGE_REPO}@${digest}"
else
  # The tag still works and extraction proceeds, but an unpinned pull is not a
  # benign detail and must not pass unrecorded: the only other signal is the
  # release-parity preflight, which is non-blocking.
  report frontend-assets warn \
    "no containerimage.digest in BAKE_METADATA for bake target '${BAKE_TARGET}', so the image is pulled by mutable tag instead of a pinned digest. If a concurrent push overwrote that tag between this run's push and this pull, the extracted assets belong to that other build and the sourcemaps uploaded under this run's release SHA are misfiled for both releases."
fi

echo "Extracting ${IMAGE_DIST_PATH} from ${IMAGE_REF}"

# --- pull --------------------------------------------------------------------
#
# Images are built for linux/amd64 + linux/arm64. The frontend bundle is
# identical in both, so pin amd64 and pull one manifest instead of the index.
#
# Everything docker says goes to the step log and stops there. This repository
# is public and both annotations and the job summary are world-readable, while
# registry error text is unbounded and controlled by a remote we merely trust —
# and GitHub masks secrets by exact value, so a credential echoed back in any
# transformed or truncated form would come through unmasked. Details reported
# from here are text this repo authored; the operator reads the log.
set +e
out="$(docker pull --platform linux/amd64 "$IMAGE_REF" 2>&1)"
rc=$?
log_docker_output "$out"
if [ "$rc" -ne 0 ]; then
  report frontend-assets blocked \
    "docker pull for bake target '${BAKE_TARGET}' exited ${rc} — the image was not published (PR builds do not push) or the registry login does not cover it, so no frontend assets could be extracted and no sourcemaps will ship. The docker output is in this step's log."
  emit_status blocked
  exit 0
fi

# Unlike the pull and the copy, this stdout is PARSED — it becomes the container
# reference for the copy below. Merging stderr into it would let any warning
# docker prints on an otherwise successful create ride along in "$cid", and the
# malformed reference would then fail the copy and be reported as a missing
# build, sending the operator to audit a frontend that is fine. Keep the streams
# apart; stderr is for the log.
create_err="$(mktemp "${RUNNER_TEMP:-/tmp}/frontend-dist-create.XXXXXX" 2>/dev/null || printf '/dev/null')"
cid="$(docker create "$IMAGE_REF" 2>"$create_err")"
rc=$?
create_msg="$(cat "$create_err" 2>/dev/null)"
[ "$create_err" = "/dev/null" ] || rm -f "$create_err"
log_docker_output "$create_msg"
if [ "$rc" -ne 0 ]; then
  report frontend-assets blocked \
    "docker create for bake target '${BAKE_TARGET}' exited ${rc}, so the pulled image could not be opened to copy the frontend tree out of it and no sourcemaps will ship. The docker output is in this step's log."
  emit_status blocked
  exit 0
fi

# Container ids are hex. Anything else means stdout carried something other than
# the id, and the copy below would fail for a reason the copy's own message
# describes wrongly. Named failure beats confident misdiagnosis. Length is left
# unchecked so a short-id format change does not block extraction.
case "$cid" in
  '' | *[!0-9a-f]*)
    log_docker_output "$cid"
    report frontend-assets blocked \
      "docker create for bake target '${BAKE_TARGET}' succeeded but did not print a container id on stdout, so there is no reference to copy the frontend tree out of and no sourcemaps will ship. The docker output is in this step's log."
    emit_status blocked
    exit 0
    ;;
esac

mkdir -p "$(dirname "$DIST_DEST")"
rm -rf "$DIST_DEST"

# `docker cp SRC DEST_DIR/` places SRC as a child of DEST_DIR. Copy to the
# parent so the tree lands at exactly $DIST_DEST.
cp_out="$(docker cp "${cid}:${IMAGE_DIST_PATH}" "$(dirname "$DIST_DEST")/" 2>&1)"
cp_rc=$?
docker rm -f "$cid" > /dev/null 2>&1

# The image path's basename may differ from the destination's; normalise.
src_landing="$(dirname "$DIST_DEST")/$(basename "$IMAGE_DIST_PATH")"
if [ "$src_landing" != "$DIST_DEST" ] && [ -d "$src_landing" ]; then
  mv "$src_landing" "$DIST_DEST"
fi

if [ "$cp_rc" -ne 0 ] || [ ! -d "$DIST_DEST" ]; then
  log_docker_output "$cp_out"
  report frontend-assets blocked \
    "docker cp of ${IMAGE_DIST_PATH} out of the image for bake target '${BAKE_TARGET}' exited ${cp_rc} — the built frontend is not where this script expects it (check vite build.outDir and the final-stage COPY of ./public). The docker output is in this step's log."
  emit_status blocked
  exit 0
fi

map_count="$(find "$DIST_DEST" -type f -name '*.map' 2>/dev/null | wc -l | tr -d ' ')"
js_count="$(find "$DIST_DEST" -type f -name '*.js' 2>/dev/null | wc -l | tr -d ' ')"

if [ "${map_count:-0}" -eq 0 ]; then
  report frontend-assets blocked \
    "extracted ${DIST_DEST} from the image for bake target '${BAKE_TARGET}' (${js_count} .js) but it contains ZERO .map files — the image was built without sourcemaps (vite.config.ts build.sourcemap) or they were stripped before the final stage. Nothing worth uploading."
  emit_status blocked
  exit 0
fi

# The image is only needed for this copy; the runner has finite disk and the
# remaining steps are all API calls.
docker image rm -f "$IMAGE_REF" > /dev/null 2>&1

report frontend-assets ok \
  "extracted ${DIST_DEST} from ${IMAGE_REF}: ${js_count} .js, ${map_count} .map"
emit_status extracted
exit 0
