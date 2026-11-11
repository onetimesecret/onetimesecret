#!/usr/bin/env bash
#
# tools/staging-pass/run-caddy.sh — the proxy for the staging pass.
#
# Runs etc/examples/Caddyfile-example from the deployed tree, unmodified,
# with the environment the proxy service gets in docker-compose.full.yml
# (DOMAIN, CERTIFICATE_EMAIL, PUBLIC_DIR) plus the upstream address of the
# app. PUBLIC_DIR is empty, as it is in the proxy image. Set CADDYFILE to
# try another configuration.
set -euo pipefail
ROOT=${STAGING_ROOT:-/srv/ots-staging}
export DOMAIN=${STAGING_DOMAIN:-secrets.staging.test} CERTIFICATE_EMAIL=ops@staging.test
export PUBLIC_DIR=$ROOT/public UPSTREAM_HOST=127.0.0.1 UPSTREAM_PORT=${UPSTREAM_PORT:-3000}
unset HTTPS_PROXY https_proxy HTTP_PROXY http_proxy
exec "${CADDY_BIN:-$ROOT/bin/caddy}" run --adapter caddyfile \
  --config "${CADDYFILE:-$ROOT/head/etc/examples/Caddyfile-example}"
