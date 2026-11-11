#!/usr/bin/env bash
#
# tools/staging-pass/prepare.sh — one-time setup for the staging pass.
#
# Builds a production-shaped install of the working tree next to the
# published image of an earlier release, so both can take turns on the same
# datastores behind the repo's Caddyfile. Every step is skipped when its
# output already exists, so a re-run is safe.
#
#   tools/staging-pass/prepare.sh
#
# Needs root (binds 80/443, adds loopback addresses, writes /etc/hosts and
# /data/caddy), docker, Ruby per .ruby-version with the bundle installed,
# `pnpm install` done, Go (for xcaddy) and openssl. See README.md for what
# each piece stands in for.
#
# This script was assembled from the commands run by hand during the
# 2026-11-11 pass; only its skip-everything re-run was exercised afterwards.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/../.." && pwd)
ROOT=${STAGING_ROOT:-/srv/ots-staging}
STATE=${STAGING_STATE:-$ROOT/state}
DOMAIN=${STAGING_DOMAIN:-secrets.staging.test}
SERVER_IP=203.0.113.1

mkdir -p "$ROOT"/{home,logs,public,bin,v19-etc} "$STATE"/{tls,results}

# --- uid 1001, the user the image runs as --------------------------------
id appuser > /dev/null 2>&1 || {
  groupadd -g 1001 appuser
  useradd -r -u 1001 -g appuser -d "$ROOT/home" -s /bin/bash appuser
}

# --- secrets and the install's env file -----------------------------------
if [ ! -f "$STATE/secrets.env" ]; then
  {
    echo "VALKEY_PASSWORD=$(openssl rand -hex 16)"
    echo "RABBITMQ_USER=ots"
    echo "RABBITMQ_PASS=$(openssl rand -hex 12)"
    echo "PG_SUPER_PASS=$(openssl rand -hex 12)"
    echo "PG_MIGRATOR_PASS=$(openssl rand -hex 12)"
    echo "PG_USER_PASS=$(openssl rand -hex 12)"
    echo "SECRET=$(openssl rand -hex 32)"
    echo "AUTH_SECRET=$(openssl rand -hex 32)"
    echo "ACCOUNT_ID_SECRET=$(openssl rand -hex 32)"
    echo "ARGON2_SECRET=$(openssl rand -hex 32)"
  } > "$STATE/secrets.env"
fi
set -a
# shellcheck disable=SC1091
. "$STATE/secrets.env"
set +a

# The variables docker-compose.full.yml gives the app, worker and scheduler,
# with jobs on and the mail sink as SMTP server. No value may contain a
# space: the file is read by docker --env-file as well as by the shell.
if [ ! -f "$ROOT/app.env" ]; then
  cat > "$ROOT/app.env" << EOF
RACK_ENV=production
SECRET=$SECRET
AUTH_SECRET=$AUTH_SECRET
ACCOUNT_ID_SECRET=$ACCOUNT_ID_SECRET
ARGON2_SECRET=$ARGON2_SECRET
HOST=$DOMAIN
SSL=true
AUTHENTICATION_MODE=full
AUTH_DATABASE_URL=sqlite://data/auth.db
VALKEY_URL=redis://:$VALKEY_PASSWORD@127.0.0.1:6479/0
RABBITMQ_URL=amqp://$RABBITMQ_USER:$RABBITMQ_PASS@127.0.0.1:5772
JOBS_ENABLED=true
JOBS_SCHEDULER_ENABLED=true
EMAILER_MODE=smtp
SMTP_HOST=127.0.0.1
SMTP_PORT=1125
SMTP_TLS=false
FROM_EMAIL=secure@staging.test
FROM_NAME=StagingSecrets
TRUSTED_PROXY_ENABLED=true
PORT=3000
EOF
fi

# --- the working tree as an install (what the image's final stage does) ----
if [ ! -d "$ROOT/head" ]; then
  mkdir -p "$ROOT/head"
  git -C "$repo" archive HEAD | tar -x -C "$ROOT/head"
  git -C "$repo" rev-parse HEAD > "$ROOT/head/.commit_hash.txt"
  [ -d "$repo/public/web/dist" ] || (cd "$repo" && pnpm run build)
  mkdir -p "$ROOT/head/public/web" "$ROOT/head/data"
  cp -a "$repo/public/web/dist" "$ROOT/head/public/web/dist"
  cp -a "$repo/generated/." "$ROOT/head/generated/"
  (
    cd "$ROOT/head"
    for file in etc/defaults/*.defaults.*; do
      cp --preserve --update=none "$file" "etc/$(basename "$file" | sed 's/\.defaults//')"
    done
    cp --preserve --update=none etc/examples/puma.example.rb etc/puma.rb
  )
  # Scheduled jobs that ship off, switched on with short schedules. The same
  # edit goes into the earlier release's own config.
  python3 "$here/patch_jobs_config.py" "$ROOT/head/etc/config.yaml"
fi
if [ ! -f "$ROOT/v19-etc/config.yaml" ]; then
  docker run --rm --entrypoint sh "${BASELINE_IMAGE:-onetimesecret/onetimesecret:v0.26.19}" \
    -c 'cat /app/etc/config.yaml' > "$ROOT/v19-etc/config.yaml"
  python3 "$here/patch_jobs_config.py" "$ROOT/v19-etc/config.yaml"
fi
chown -R appuser:appuser "$ROOT/head" "$ROOT/home" "$ROOT/logs" "$ROOT/v19-etc"

# --- the proxy: same Caddy commit and plugins as docker/variants/caddy.dockerfile
if [ ! -x "$ROOT/bin/caddy" ]; then
  build=$(mktemp -d)
  (
    cd "$build"
    export GOPATH="$build/go" GOFLAGS=-mod=mod GOTOOLCHAIN=auto
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@328cac711a1fe80041c3b79db2dfbb4e10330a05
    "$GOPATH/bin/xcaddy" build e2eee6a7fce366321294c9c2a79f3146891dcbdf --output "$ROOT/bin/caddy" \
      --with github.com/mholt/caddy-ratelimit \
      --with github.com/greenpau/caddy-security@a20b782cd19a11659e71b88ffcce3fdd3437a526 \
      --with github.com/caddyserver/transform-encoder \
      --with github.com/caddy-dns/cloudflare
  )
fi

# --- a certificate the unmodified Caddyfile can serve ----------------------
# The Caddyfile forces the ACME issuer, which cannot issue for a test name.
# Caddy uses a certificate it finds in its storage, so one signed by a
# throwaway CA is placed where the ACME issuer would have stored it.
if [ ! -f "$STATE/tls/ca.crt" ]; then
  t=$STATE/tls
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout "$t/ca.key" -out "$t/ca.crt" \
    -days 30 -subj "/CN=OTS Staging Test CA" -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" -addext "subjectKeyIdentifier=hash" 2> /dev/null
  openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout "$t/leaf.key" -out "$t/leaf.csr" \
    -subj "/CN=$DOMAIN" 2> /dev/null
  printf 'subjectAltName=DNS:%s\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=serverAuth\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid\n' \
    "$DOMAIN" > "$t/ext.cnf"
  openssl x509 -req -in "$t/leaf.csr" -CA "$t/ca.crt" -CAkey "$t/ca.key" -CAcreateserial -out "$t/leaf.crt" \
    -days 30 -extfile "$t/ext.cnf" 2> /dev/null
fi
store=/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$DOMAIN
if [ ! -f "$store/$DOMAIN.crt" ]; then
  mkdir -p "$store"
  cat "$STATE/tls/leaf.crt" "$STATE/tls/ca.crt" > "$store/$DOMAIN.crt"
  cp "$STATE/tls/leaf.key" "$store/$DOMAIN.key"
  chmod 600 "$store/$DOMAIN.key"
  printf '{"sans":["%s"],"issuer_data":null}\n' "$DOMAIN" > "$store/$DOMAIN.json"
fi

# --- public-range addresses on loopback -------------------------------------
# The Caddyfile trusts private ranges, so a client on 127.0.0.1 is treated as
# a trusted proxy. Documentation-range addresses (RFC 5737) make the test
# clients look like public peers, each with its own address.
grep -q " $DOMAIN\$" /etc/hosts || echo "$SERVER_IP $DOMAIN" >> /etc/hosts
add_ip() {
  if command -v ip > /dev/null 2>&1; then
    ip addr add "$1/32" dev lo 2> /dev/null || true
  else
    docker run --rm --network host --cap-add NET_ADMIN busybox:1.37 ip addr add "$1/32" dev lo 2> /dev/null || true
  fi
}
if ! getent hosts "$DOMAIN" > /dev/null || ! ping -c1 -W1 203.0.113.69 > /dev/null 2>&1; then
  add_ip "$SERVER_IP"
  for i in $(seq 10 69); do add_ip "203.0.113.$i"; done
  for i in $(seq 10 49); do
    add_ip "198.51.100.$i"
    add_ip "192.0.2.$i"
  done
fi

# --- backing services and the Postgres auth database ------------------------
docker ps --format '{{.Names}}' | grep -qx stg-valkey || "$here/services.sh" up
if [ ! -f "$STATE/pg-init.sql" ]; then
  sed -e "s/CHANGE_ME_MIGRATION_PASSWORD/$PG_MIGRATOR_PASS/; s/CHANGE_ME_APPLICATION_PASSWORD/$PG_USER_PASS/" \
    "$repo/apps/web/auth/migrations/schemas/postgres/initialize_auth_db.sql" > "$STATE/pg-init.sql"
fi

echo "prepared: $ROOT (state in $STATE)"
