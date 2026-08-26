#!/usr/bin/env bash
#
# scripts/ci/sentry-sourcemap-preflight.sh
#
# Pre-upload assertions for the "Upload frontend sourcemaps to Sentry" step of
# .github/workflows/build-and-publish-oci-images.yml.
#
# WHY THIS EXISTS
#
# `sentry-cli sourcemaps upload <dir>` is happy to upload nothing. Combined
# with `continue-on-error: true` on the step, a build that ships zero artifacts
# is indistinguishable from one that ships a complete bundle set: both are
# green, both print a couple of lines nobody reads. This script turns the four
# ways that delivery silently rots into loud, durable signals:
#
#   1. credentials configured but the dist tree / .map files are absent
#      (nothing to upload — the upload would "succeed" with zero artifacts);
#   2. the admin bundle (src/admin.ts, second vite pass) missing from the tree
#      while the customer bundle is present — the Colonel console's traces
#      would be the only unsymbolicated ones, which is exactly the kind of
#      partial failure nobody notices;
#   3. the release string used for upload not matching the __SENTRY_RELEASE__
#      value baked into the bundles by vite.config.ts (a bundle filed under a
#      release no event will ever report);
#   4. the upload's --project / --dist not matching what a frontend event
#      actually carries (bundles that exist but can never resolve).
#
# It NEVER exits non-zero. It classifies, reports via scripts/ci/sentry-status.sh,
# and writes `status=` to $GITHUB_OUTPUT so the workflow can decide whether the
# upload is worth attempting:
#
#   status=skipped   no credentials — quiet, expected on forks/PRs
#   status=blocked   credentials present, preconditions failed — loud, no upload
#   status=ready     go ahead and upload (possibly with warnings recorded)
#
# Environment:
#   SENTRY_AUTH_TOKEN   presence is what separates SKIPPED from FAILED
#   SENTRY_ORG          required by sentry-cli alongside the token
#   SENTRY_PROJECTS     space-separated slugs the release step uses
#   SENTRY_PROJECT      slug the sourcemap upload targets (default: frontend)
#   SENTRY_DIST         dist tag the upload applies (default: empty = none)
#   SENTRY_RELEASE      release the upload tags bundles with
#   SENTRY_DIST_DIR     built frontend tree (default: ./public/web/dist)
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATUS="${REPO_ROOT}/scripts/ci/sentry-status.sh"

DIST_DIR="${SENTRY_DIST_DIR:-./public/web/dist}"
UPLOAD_PROJECT="${SENTRY_PROJECT:-frontend}"
UPLOAD_DIST="${SENTRY_DIST:-}"
RELEASE="${SENTRY_RELEASE:-}"

# Only two places can put a `dist` on a frontend event: the Sentry.init options
# literal, and the backend-supplied config spread into it (`...config.sentry`).
# Neither can establish that a dist IS present — see section 6, which reads that
# off the built chunks — but both explain a negative result, which is the
# difference between "the frontend sets nothing" and "the frontend sets
# something this script cannot read".
DIAGNOSTICS_TS="${REPO_ROOT}/src/plugins/core/enableDiagnostics.ts"
CONFIG_SERIALIZER="${REPO_ROOT}/apps/web/core/views/serializers/config_serializer.rb"

warnings=0

report() { bash "$STATUS" record "$@"; }
warn() {
  warnings=$((warnings + 1))
  report "$@"
}

emit_status() {
  local value="$1"
  echo "status=${value}" >> "${GITHUB_OUTPUT:-/dev/null}"
  echo "sourcemap preflight: ${value} (${warnings} warning(s))"
}

have_glob() { compgen -G "$1" > /dev/null 2>&1; }

# --- 1. credentials: SKIPPED vs everything else ------------------------------
#
# No token means nobody configured Sentry here. That is the normal state of a
# fork and of any self-hosted clone, and it must stay quiet. Every other
# failure below is reachable ONLY when a token is present, which is what makes
# those failures worth shouting about.
if [ -z "${SENTRY_AUTH_TOKEN:-}" ]; then
  report sourcemaps skipped "SENTRY_AUTH_TOKEN not configured; no upload attempted"
  emit_status skipped
  exit 0
fi

if [ -z "${SENTRY_ORG:-}" ]; then
  report sourcemaps blocked \
    "SENTRY_AUTH_TOKEN is set but SENTRY_ORG is empty — sentry-cli cannot resolve a target org. Set the SENTRY_ORG repository secret."
  emit_status blocked
  exit 0
fi

if [ -z "$RELEASE" ]; then
  report sourcemaps blocked \
    "SENTRY_RELEASE resolved empty — bundles would be uploaded under an anonymous release and never match an event."
  emit_status blocked
  exit 0
fi

# --- 2. the dist tree must exist and carry sourcemaps ------------------------
#
# This is the assertion that has been missing. public/web/dist is gitignored
# and the frontend is compiled INSIDE the OCI image (Dockerfile: pnpm run
# build), so unless the workflow explicitly materialises the tree on the runner
# there is nothing here to upload.
if [ ! -d "$DIST_DIR" ]; then
  report sourcemaps blocked \
    "${DIST_DIR} does not exist on the runner — nothing was uploaded. The frontend is built inside the OCI image, so the job must either run 'pnpm run build' or extract ${DIST_DIR} out of the built image before this step."
  emit_status blocked
  exit 0
fi

map_count="$(find "$DIST_DIR" -type f -name '*.map' 2>/dev/null | wc -l | tr -d ' ')"
if [ "${map_count:-0}" -eq 0 ]; then
  report sourcemaps blocked \
    "${DIST_DIR} exists but contains zero .map files — the upload would have reported success while shipping nothing. Check that vite build.sourcemap is still true and that the whole dist tree was copied."
  emit_status blocked
  exit 0
fi

# --- 3. both bundles, not just the customer one ------------------------------
#
# package.json 'build' runs vite twice: the customer pass (src/main.ts) then
# the admin pass (src/admin.ts, emptyOutDir: false, .vite/manifest-admin.json).
# Both are instrumented — src/main.ts and src/admin.ts each construct the
# AppInitializer that calls createDiagnostics(). A tree with only the first
# pass is a half-delivery.
main_ok=0
admin_ok=0
have_glob "${DIST_DIR}/assets/main.*.js.map" && main_ok=1
have_glob "${DIST_DIR}/assets/admin.*.js.map" && admin_ok=1
[ -f "${DIST_DIR}/.vite/manifest-admin.json" ] || admin_ok=0

if [ "$main_ok" -eq 0 ] && [ "$admin_ok" -eq 0 ]; then
  report sourcemaps blocked \
    "found ${map_count} .map file(s) in ${DIST_DIR} but no entry sourcemap for either bundle (expected assets/main.*.js.map and assets/admin.*.js.map) — the tree is not a completed two-pass vite build."
  emit_status blocked
  exit 0
fi

if [ "$main_ok" -eq 0 ]; then
  warn sourcemaps warn \
    "customer bundle sourcemap missing (no ${DIST_DIR}/assets/main.*.js.map) — customer-facing stack traces for release ${RELEASE} will not symbolicate."
fi

if [ "$admin_ok" -eq 0 ]; then
  warn sourcemaps warn \
    "admin bundle missing or incomplete (want ${DIST_DIR}/assets/admin.*.js.map and ${DIST_DIR}/.vite/manifest-admin.json) — the second vite pass (VITE_BUILD_TARGET=admin) did not land, so Colonel console traces will not symbolicate."
fi

# --- 4. release parity with __SENTRY_RELEASE__ -------------------------------
#
# vite.config.ts defines __SENTRY_RELEASE__ = JSON.stringify(getSentryRelease())
# and enableDiagnostics.ts sets `release: __SENTRY_RELEASE__` AFTER the
# `...config.sentry` spread, so the build-time value is what every frontend
# event reports. getSentryRelease() resolves SENTRY_RELEASE -> .commit_hash.txt
# -> git rev-parse -> 'dev'. Inside the image it takes the .commit_hash.txt
# branch, which the workflow and the Dockerfile both write from the same short
# SHA — but nothing enforces that, and a divergence files the bundles under a
# release no event will ever claim.
#
# The define is inlined as a plain string literal, so its presence in the
# emitted entry chunks is a direct, if coarse, check. There is no build-emitted
# release manifest to compare against exactly; see the note below.
if grep -RIlF -- "$RELEASE" "${DIST_DIR}"/assets/*.js > /dev/null 2>&1; then
  report release-parity ok \
    "upload release '${RELEASE}' found inlined in the built entry chunks (__SENTRY_RELEASE__ match)"
else
  warn release-parity warn \
    "upload release '${RELEASE}' does not appear in any ${DIST_DIR}/assets/*.js — __SENTRY_RELEASE__ baked at build time is probably a different value, so events will report a release these bundles are not filed under. Check that .commit_hash.txt in the build context matched steps.commit.outputs.short_sha."
fi

# --- 5. project routing ------------------------------------------------------
#
# The release step creates/finalizes the release against $SENTRY_PROJECTS. The
# upload hardcodes its own project. If the upload's project is not among them,
# the release and its artifact bundles live in different places and neither
# half is obviously wrong on its own.
#
# The details below carry COUNTS, never slugs. SENTRY_PROJECTS and
# SENTRY_FRONTEND_PROJECT are repository secrets, and GitHub masks a secret only
# by exact value: sentry-status.sh truncates an over-long detail at a whitespace
# boundary, and SENTRY_PROJECTS is a space-separated list, so a long value can be
# cut BETWEEN slugs and published as an unmasked prefix that no longer matches
# what was registered. Whether the upload's project is among the configured set
# is the whole finding; which slugs those are adds nothing an operator with
# access to the secrets cannot already read.
if [ -n "${SENTRY_PROJECTS:-}" ]; then
  project_match=0
  project_count=0
  for proj in $SENTRY_PROJECTS; do
    project_count=$((project_count + 1))
    [ "$proj" = "$UPLOAD_PROJECT" ] && project_match=1
  done
  if [ "$project_match" -eq 0 ]; then
    warn project-routing warn \
      "the sourcemaps upload targets a project that is not among the ${project_count} configured project(s) the release was created for — the artifact bundles and the release will not be in the same project. Reconcile SENTRY_FRONTEND_PROJECT against SENTRY_PROJECTS."
  else
    report project-routing ok \
      "the upload's project is among the ${project_count} configured project(s) the release was created for"
  fi
else
  warn project-routing warn \
    "SENTRY_PROJECTS is empty, so no Sentry release exists to attach bundles to; the upload will proceed against its configured project regardless."
fi

# --- 6. dist-tag contract ----------------------------------------------------
#
# A `dist` is a JOIN KEY: Sentry only resolves an artifact bundle for an event
# when release AND dist both match. Tagging the upload --dist=X while the
# frontend sets no dist means the bundles can never resolve — the exact failure
# mode that looks like a successful upload.
#
# The affirmative answer comes from where the release check gets its own: the
# BUILT chunks. Whatever the frontend hands Sentry.init — a literal, a constant,
# a vite define — resolves to a quoted string in the emitted bundle, so finding
# `dist:"X"` there is evidence an event will actually carry X. Source greps
# cannot produce that evidence and must never be allowed to stand in for it: a
# dist arriving at runtime through the `...config.sentry` spread is invisible to
# them, and any grep over source rots the moment the source is refactored.
#
# So the only path to `ok` is the built output. Everything else is a warning,
# including — especially — the cases where this script cannot tell. "We could
# not determine it" reported as "we verified it matches" is how the join key
# broke unnoticed in the first place.
dist_in_bundle=0
if [ -n "$UPLOAD_DIST" ]; then
  # Fixed strings, not a regex, so a dist containing regex metacharacters cannot
  # loosen the match. The build minifies to a single chunk and minifiers do not
  # quote keys that are valid identifiers, hence the bare `dist:`; the spaced
  # forms cover an unminified tree.
  for needle in "dist:\"${UPLOAD_DIST}\"" "dist:'${UPLOAD_DIST}'" \
                "dist: \"${UPLOAD_DIST}\"" "dist: '${UPLOAD_DIST}'"; do
    if grep -RIlF -- "$needle" "${DIST_DIR}"/assets/*.js > /dev/null 2>&1; then
      dist_in_bundle=1
      break
    fi
  done
fi

# Source signals. Used only to explain a negative result, never to satisfy one.
# `diag_sets_dist` without `frontend_dist` means enableDiagnostics.ts sets a
# dist that is not a readable literal.
diag_sets_dist=0
frontend_dist=""
if grep -qE '^[[:space:]]*dist:[[:space:]]*[^[:space:]]' "$DIAGNOSTICS_TS" 2>/dev/null; then
  diag_sets_dist=1
  frontend_dist="$(sed -nE "s/^[[:space:]]*dist:[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p" \
    "$DIAGNOSTICS_TS" | head -n1)"
fi

# Anchored at the start of the line so a commented-out key cannot match, and
# limited to the three ways Ruby writes a hash key.
backend_sets_dist=0
if grep -qE "^[[:space:]]*['\"]?dist['\"]?[[:space:]]*(:|=>)" "$CONFIG_SERIALIZER" 2>/dev/null; then
  backend_sets_dist=1
fi

if [ -z "$UPLOAD_DIST" ]; then
  if [ -n "$frontend_dist" ]; then
    warn dist-tag warn \
      "frontend events carry dist='${frontend_dist}' but the upload passes no --dist — bundles are filed dist-less and will not resolve. Pass --dist='${frontend_dist}'."
  elif [ "$diag_sets_dist" -eq 1 ] || [ "$backend_sets_dist" -eq 1 ]; then
    warn dist-tag warn \
      "the upload passes no --dist, and a dist is set somewhere this check cannot read back (enableDiagnostics.ts non-literal: ${diag_sets_dist}, backend diagnostics config: ${backend_sets_dist}) — if events carry one, these dist-less bundles will not resolve. Join key UNVERIFIED."
  else
    report dist-tag ok "neither the upload nor the frontend sets a dist (consistent)"
  fi
elif [ "$dist_in_bundle" -eq 1 ]; then
  report dist-tag ok \
    "upload --dist='${UPLOAD_DIST}' found inlined in the built entry chunks — events from this build carry the same dist"
elif [ -n "$frontend_dist" ] && [ "$frontend_dist" != "$UPLOAD_DIST" ]; then
  warn dist-tag warn \
    "dist mismatch: upload uses --dist='${UPLOAD_DIST}', src/plugins/core/enableDiagnostics.ts sets dist='${frontend_dist}'."
elif [ -n "$frontend_dist" ]; then
  warn dist-tag warn \
    "src/plugins/core/enableDiagnostics.ts sets dist='${frontend_dist}' matching the upload, but no chunk in ${DIST_DIR}/assets carries it — this tree was built before that change landed, or the value was stripped, so events from THIS build still carry no dist."
elif [ "$diag_sets_dist" -eq 1 ] || [ "$backend_sets_dist" -eq 1 ]; then
  warn dist-tag warn \
    "upload tags bundles with --dist='${UPLOAD_DIST}' and no built chunk carries that dist, but a dist is set somewhere this check cannot read back (enableDiagnostics.ts non-literal: ${diag_sets_dist}, backend diagnostics config: ${backend_sets_dist}) — the join key is UNVERIFIED, not confirmed. Resolve it to a build-time value so the built chunks can be checked."
else
  warn dist-tag warn \
    "upload tags bundles with --dist='${UPLOAD_DIST}' but no built chunk carries a dist and the frontend sets none (neither src/plugins/core/enableDiagnostics.ts nor the backend diagnostics config emits one), so events carry dist=undefined and will never resolve these bundles. Drop --dist from the upload, or set a matching dist in Sentry.init."
fi

emit_status ready
exit 0
