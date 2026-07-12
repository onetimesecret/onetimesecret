#!/usr/bin/env bash
#
# scripts/test-install/run.sh
#
# Tier-1 clean-room harness (install-onboarding testing-strategy §2). Runs a
# documented install path from ZERO inside a pinned base image, so a maintainer
# can experience a fresh install from a poisoned laptop, and CI runs the exact
# same artifact (installer.yml — testing-strategy §2b).
#
# Each lane = one `docker run --rm` against a PINNED image. The repo is copied
# in with `git archive HEAD` (never a writable bind-mount — that would leak host
# state, caches, and your working tree into the "clean" room).
#
# Lanes:
#   baremetal   ruby:3.4.9-slim — the documented floor. install.sh init must
#               succeed, produce a .env with a real SECRET, and be idempotent.
#   ruby-old    ruby:3.3-slim   — install.sh init must FAIL with a clear
#               "need exactly 3.4.9" message (an asserted-error lane; NF-5).
#   posix       ruby:3.4.9-slim with an empty locale — the container default IS
#               POSIX, which is the fresh-server repro for the old locale crash
#               (must now pass; C3 fixed it). We assert LANG stays unset.
#
# Usage:
#   scripts/test-install/run.sh --lane baremetal
#   scripts/test-install/run.sh --lane ruby-old
#   scripts/test-install/run.sh --lane posix
#   scripts/test-install/run.sh --lane all
#
# Requires a working Docker daemon. Not run by the fresh-clone lane (that one
# needs no container); this is the installer-matrix harness.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

LANE="baremetal"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lane) LANE="${2:?--lane needs a value}"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

# Pinned base images per lane (exact patch for the Ruby-version gate).
IMAGE_BAREMETAL="ruby:3.4.9-slim"
IMAGE_RUBY_OLD="ruby:3.3-slim"

# Toolchain setup mirrored from docker/base.dockerfile so the container has
# exactly what a documented bare-metal install needs — no more, no less.
# (build deps for pg/sqlite3/argon2/bcrypt/puma, Node 22, pnpm, redis, procps.)
read -r -d '' SETUP_TOOLCHAIN <<'SETUP' || true
  set -eux
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends \
    build-essential libssl-dev libffi-dev libyaml-dev libsqlite3-dev \
    libpq-dev libsodium23 pkg-config git curl ca-certificates \
    python3 procps redis-server
  # Node 22 (matches .node-version) via NodeSource; pnpm pinned to packageManager.
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y --no-install-recommends nodejs
  npm install -g pnpm@11.10.0
  redis-server --daemonize yes
  node --version; ruby --version; pnpm --version
SETUP

# Post-conditions asserted after a successful install (behavior, not exit code
# alone): a .env exists with a >=32-char SECRET, and a second run is clean.
read -r -d '' ASSERT_AND_IDEMPOTENT <<'ASSERT' || true
  echo "--- post-conditions ---"
  test -s .env || { echo "FAIL: .env missing/empty"; exit 1; }
  grep -qE '^SECRET=.{32,}' .env || { echo "FAIL: .env has no >=32-char SECRET"; exit 1; }
  echo "OK: .env present with a real SECRET"
  echo "--- idempotency re-run ---"
  ./install.sh init
  echo "OK: second install.sh init succeeded (idempotent)"
ASSERT

# run_in_image <image> <lane-label> <inner-script>
# Copies HEAD into the container via git archive and runs the inner script.
run_in_image() {
  local image="$1" label="$2" inner="$3"
  echo "==================================================================="
  echo "  lane: $label   image: $image"
  echo "==================================================================="
  git archive --format=tar HEAD | docker run --rm -i \
    -e DEBIAN_FRONTEND=noninteractive \
    "$image" bash -c '
      set -euo pipefail
      mkdir -p /src && cd /src && tar -x
      '"$inner"'
    '
}

lane_baremetal() {
  run_in_image "$IMAGE_BAREMETAL" "baremetal" "
    $SETUP_TOOLCHAIN
    echo '--- install.sh init (documented floor) ---'
    ./install.sh init
    $ASSERT_AND_IDEMPOTENT
  "
}

lane_posix() {
  # Explicitly assert the environment is a POSIX/empty locale — the fresh-server
  # condition that used to crash rake ots:secrets / puma boot.
  run_in_image "$IMAGE_BAREMETAL" "posix-locale" "
    unset LANG LC_ALL LANGUAGE || true
    echo \"locale is: LANG='\${LANG:-}' LC_ALL='\${LC_ALL:-}'\"
    [ -z \"\${LANG:-}\" ] || { echo 'FAIL: expected empty LANG'; exit 1; }
    $SETUP_TOOLCHAIN
    echo '--- install.sh init under POSIX locale ---'
    ./install.sh init
    $ASSERT_AND_IDEMPOTENT
  "
}

lane_ruby_old() {
  # Asserted-error lane: install.sh init MUST fail fast with the exact-match
  # Ruby gate (NF-5). A clean, actionable failure is the pass condition here.
  echo "==================================================================="
  echo "  lane: ruby-old (expect a clear version-gate failure)   image: $IMAGE_RUBY_OLD"
  echo "==================================================================="
  local out status
  out="$(git archive --format=tar HEAD | docker run --rm -i "$IMAGE_RUBY_OLD" bash -c '
    set -uo pipefail
    mkdir -p /src && cd /src && tar -x
    ./install.sh init
  ' 2>&1)" && status=0 || status=$?
  echo "$out"
  if [[ "$status" -eq 0 ]]; then
    echo "FAIL: install.sh init succeeded on old Ruby — the version gate did not fire"
    exit 1
  fi
  if echo "$out" | grep -qiE 'need exactly 3\.4\.9|version mismatch|too old'; then
    echo "OK: install.sh init failed with a clear Ruby-version message (exit $status)"
  else
    echo "FAIL: install.sh init failed (exit $status) but not with the expected version message"
    exit 1
  fi
}

case "$LANE" in
  baremetal) lane_baremetal ;;
  posix)     lane_posix ;;
  ruby-old)  lane_ruby_old ;;
  all)       lane_baremetal; lane_posix; lane_ruby_old ;;
  *) echo "unknown lane: $LANE (want: baremetal|posix|ruby-old|all)" >&2; exit 64 ;;
esac

echo ""
echo "clean-room lane(s) passed: $LANE"
