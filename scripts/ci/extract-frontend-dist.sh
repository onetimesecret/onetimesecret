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
#   BAKE_METADATA      docker/bake-action `metadata` output (JSON). When it
#                      carries a digest the pull is digest-pinned, which is
#                      immune to a tag being overwritten between push and pull.
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
if [ -n "${BAKE_METADATA:-}" ]; then
  digest="$(printf '%s' "$BAKE_METADATA" \
    | jq -r --arg t "$BAKE_TARGET" '.[$t]["containerimage.digest"] // empty' 2>/dev/null)"
  if [ -n "$digest" ]; then
    # Strip the tag, not a registry port: only the trailing ":..." that carries
    # no "/" is a tag (ghcr.io/x/y:tag vs registry.example:5000/x/y).
    IMAGE_REPO="$IMAGE_REF"
    case "${IMAGE_REF##*:}" in
      */*) : ;;                       # ":5000/x/y" — no tag present
      *)   IMAGE_REPO="${IMAGE_REF%:*}" ;;
    esac
    IMAGE_REF="${IMAGE_REPO}@${digest}"
  fi
fi

echo "Extracting ${IMAGE_DIST_PATH} from ${IMAGE_REF}"

# --- pull --------------------------------------------------------------------
#
# Images are built for linux/amd64 + linux/arm64. The frontend bundle is
# identical in both, so pin amd64 and pull one manifest instead of the index.
set +e
out="$(docker pull --platform linux/amd64 "$IMAGE_REF" 2>&1)"
rc=$?
printf '%s\n' "$out" | tail -n 5
if [ "$rc" -ne 0 ]; then
  report frontend-assets blocked \
    "docker pull of ${IMAGE_REF} exited ${rc} — the image was not published (PR builds do not push) or the registry login does not cover it, so no frontend assets could be extracted and no sourcemaps will ship: $(printf '%s' "$out" | tail -n 2)"
  emit_status blocked
  exit 0
fi

cid="$(docker create "$IMAGE_REF" 2>&1)"
rc=$?
if [ "$rc" -ne 0 ]; then
  report frontend-assets blocked \
    "docker create from ${IMAGE_REF} exited ${rc}: $(printf '%s' "$cid" | tail -n 2)"
  emit_status blocked
  exit 0
fi

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
  report frontend-assets blocked \
    "docker cp ${IMAGE_DIST_PATH} out of ${IMAGE_REF} exited ${cp_rc} — the built frontend is not where this script expects it (check vite build.outDir and the final-stage COPY of ./public): $(printf '%s' "$cp_out" | tail -n 2)"
  emit_status blocked
  exit 0
fi

map_count="$(find "$DIST_DEST" -type f -name '*.map' 2>/dev/null | wc -l | tr -d ' ')"
js_count="$(find "$DIST_DEST" -type f -name '*.js' 2>/dev/null | wc -l | tr -d ' ')"

if [ "${map_count:-0}" -eq 0 ]; then
  report frontend-assets blocked \
    "extracted ${DIST_DEST} from ${IMAGE_REF} (${js_count} .js) but it contains ZERO .map files — the image was built without sourcemaps (vite.config.ts build.sourcemap) or they were stripped before the final stage. Nothing worth uploading."
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
