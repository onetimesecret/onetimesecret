#!/usr/bin/env bash
#
# release-sweep.sh
#
# Runs topology-probe.sh against a series of PUBLISHED RELEASE IMAGES and
# reports the release at which each topology's verdict changed. This is the
# "which version started doing this" instrument.
#
# Why images and not `git bisect`: the host seam is not owned by this repo
# alone. What `request.host` returns for a given wire request is decided by the
# rack version, otto's Rack::DetectHost, the middleware order, and the app code
# together. A release image pins all four at once, which is the only
# combination that ever actually ran in production. Bisecting the source tree
# with today's Gemfile.lock would silently hold the most likely culprit fixed.
#
# Each release gets a FRESH app container against a SHARED probe datastore, so
# the fixture is seeded once and every release reads the same records. That is
# deliberate: a release that cannot read the fixture an adjacent release wrote
# is model/index drift, and the matrix should show it rather than hide it
# behind a re-seed.
#
# The probe datastore is its own valkey/postgres pair on dedicated ports. It
# never touches the shared 2163/2154 test datastore.
#
# Usage:
#   scripts/host-seam/release-sweep.sh v0.26.0 v0.26.1 v0.26.2 v0.26.3 v0.26.4 v0.26.5
#   scripts/host-seam/release-sweep.sh --keep v0.26.4 v0.26.5     # leave stack up
#
# Env:
#   IMAGE_REPO   default ghcr.io/onetimesecret/onetimesecret
#   APP_PORT     host port for the app under test (default 17143)
#   CANONICAL    canonical host the app is configured with (default dev.onetime.dev)
#   CUSTOM       seeded custom domain (default local-secrets1.afb.pet)
#   SECRET, ACCOUNT_ID_SECRET  generated per-sweep if unset
#
# Output: a per-release matrix on stderr, a combined TSV at
#   ./tmp/host-seam/sweep-<timestamp>.tsv, and a transition report at the end.
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

IMAGE_REPO="${IMAGE_REPO:-ghcr.io/onetimesecret/onetimesecret}"
APP_PORT="${APP_PORT:-17143}"
CANONICAL="${CANONICAL:-dev.onetime.dev}"
CUSTOM="${CUSTOM:-local-secrets1.afb.pet}"
NET="host-seam-net"
VALKEY_CT="host-seam-valkey"
APP_CT="host-seam-app"
KEEP=0

if [[ "${1:-}" == "--keep" ]]; then KEEP=1; shift; fi
[[ $# -gt 0 ]] || { echo "FATAL: name at least one release tag" >&2; exit 2; }
TAGS=("$@")

command -v podman >/dev/null || { echo "FATAL: podman not found" >&2; exit 2; }

# Secrets are per-sweep and disposable — the probe never stores anything worth
# protecting. Stable across the sweep so every release sees the same datastore.
export SECRET="${SECRET:-$(openssl rand -hex 32)}"
export ACCOUNT_ID_SECRET="${ACCOUNT_ID_SECRET:-$(openssl rand -hex 32)}"

OUT_DIR="tmp/host-seam"
mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
TSV="${OUT_DIR}/sweep-${STAMP}.tsv"
printf 'release\ttopology\tstrategy\tdisplay_domain\tsso\tverdict\n' >"$TSV"

log() { printf '\n=== %s\n' "$*" >&2; }

cleanup_app() { podman rm -f "$APP_CT" >/dev/null 2>&1 || true; }
cleanup_all() {
  cleanup_app
  if [[ $KEEP -eq 0 ]]; then
    podman rm -f "$VALKEY_CT" >/dev/null 2>&1 || true
    podman network rm "$NET"  >/dev/null 2>&1 || true
  else
    printf 'kept: %s / %s (remove with: podman rm -f %s; podman network rm %s)\n' \
      "$VALKEY_CT" "$NET" "$VALKEY_CT" "$NET" >&2
  fi
}
trap cleanup_all EXIT

# --- Probe datastore -------------------------------------------------------
log "probe datastore"
podman network create "$NET" >/dev/null 2>&1 || true
podman rm -f "$VALKEY_CT" >/dev/null 2>&1 || true
podman run -d --name "$VALKEY_CT" --network "$NET" \
  docker.io/valkey/valkey:8.1-bookworm \
  valkey-server --save '' --appendonly no >/dev/null \
  || { echo "FATAL: could not start probe valkey" >&2; exit 1; }

# --- Per-release loop ------------------------------------------------------
for tag in "${TAGS[@]}"; do
  image="${IMAGE_REPO}:${tag}"
  log "$tag — pulling $image"
  if ! podman pull "$image" >/dev/null 2>&1; then
    printf '%s\t-\t-\t-\t-\tIMAGE_UNAVAILABLE\n' "$tag" >>"$TSV"
    echo "SKIP $tag: image not pullable" >&2
    continue
  fi

  cleanup_app
  podman run -d --name "$APP_CT" --network "$NET" \
    -p "127.0.0.1:${APP_PORT}:3000" \
    -e RACK_ENV=production \
    -e HOST="$CANONICAL" \
    -e SSL=true \
    -e VALKEY_URL="redis://${VALKEY_CT}:6379/0" \
    -e REDIS_URL="redis://${VALKEY_CT}:6379/0" \
    -e AUTH_DATABASE_URL="sqlite://data/auth.db" \
    -e AUTHENTICATION_MODE=full \
    -e ORGS_SSO_ENABLED=true \
    -e SECRET="$SECRET" \
    -e ACCOUNT_ID_SECRET="$ACCOUNT_ID_SECRET" \
    -e SESSION_SECRET="$SECRET" \
    -e AUTH_SECRET="$SECRET" \
    -e JOBS_ENABLED=false \
    `# filter mode auto-trusts RFC1918/loopback, which is where the probe` \
    `# arrives from through podman's bridge. Without this DetectHost` \
    `# discards every forwarded header and T3-T5 collapse to canonical for` \
    `# a reason that has nothing to do with the bug under investigation.` \
    -e TRUSTED_PROXY_ENABLED=true \
    -e TRUSTED_PROXY_MODE=filter \
    "$image" >/dev/null 2>&1 \
    || { printf '%s\t-\t-\t-\t-\tSTART_FAILED\n' "$tag" >>"$TSV"; echo "SKIP $tag: container would not start" >&2; continue; }

  # --- Readiness --------------------------------------------------------
  ready=0
  for _ in $(seq 1 60); do
    if curl -sS -m 3 -o /dev/null "http://127.0.0.1:${APP_PORT}/" 2>/dev/null; then ready=1; break; fi
    sleep 2
  done
  if [[ $ready -eq 0 ]]; then
    printf '%s\t-\t-\t-\t-\tNEVER_READY\n' "$tag" >>"$TSV"
    echo "SKIP $tag: never became ready — logs follow" >&2
    podman logs --tail 30 "$APP_CT" >&2 2>&1 || true
    continue
  fi

  # --- Fixture (idempotent; only the first release actually writes) ------
  podman exec -i -e HOST_SEAM_DOMAIN="$CUSTOM" "$APP_CT" \
    bin/ots console <scripts/host-seam/seed-tenant.rb >/dev/null 2>&1 \
    || echo "WARN $tag: seeding reported an error (SSO column may read NO_CONFIG)" >&2

  # --- Probe ------------------------------------------------------------
  scripts/host-seam/topology-probe.sh \
    --base "http://127.0.0.1:${APP_PORT}" \
    --canonical "$CANONICAL" \
    --custom "$CUSTOM" \
    --label "$tag" \
    --tsv >>"$TSV"
done

cleanup_app

# --- Transition report -----------------------------------------------------
# The answer to "which version started having this" is the row where a
# topology's verdict flips. Everything else in the matrix is context.
log "transition report"
awk -F'\t' 'NR>1 {
  key = $2
  if (key in prev && prev[key] != $6) {
    printf "  %-22s %-18s -> %-18s at %s (was %s)\n", key, prev[key], $6, $1, prevtag[key]
    changed = 1
  }
  prev[key] = $6; prevtag[key] = $1
}
END { if (!changed) print "  no verdict changed across the sweep — the seam behaved identically in every release probed" }' "$TSV" >&2

printf '\nfull matrix: %s\n' "$TSV" >&2
