#!/usr/bin/env bash
#
# tools/staging-pass/services.sh — backing services for the staging pass.
#
# Images and commands are the ones docker/compose/docker-compose.full.yml
# pins for valkey and rabbitmq, the test compose's postgres pin and the
# mailpit compose pin. Ports are published on loopback, away from both the
# canonical ports and the 21xx test-lane ports, so nothing here can reach
# dev or lane data.
#
#   tools/staging-pass/services.sh up|down
set -euo pipefail
ROOT=${STAGING_ROOT:-/srv/ots-staging}
STATE=${STAGING_STATE:-$ROOT/state}
set -a
# shellcheck disable=SC1091
. "$STATE/secrets.env"
set +a

VALKEY_IMG='valkey/valkey:8.1-bookworm@sha256:fea8b3e67b15729d4bb70589eb03367bab9ad1ee89c876f54327fc7c6e618571'
RABBIT_IMG='rabbitmq:4.2-management@sha256:2f5f2d5551a7c11e09c57b00ff6a86f363ddd424e3bde3a54c88a75c742a81e8'
PG_IMG='postgres:17@sha256:b994732fcf33f73776c65d3a5bf1f80c00120ba5007e8ab90307b1a743c1fc16'
MAILPIT_IMG='axllent/mailpit@sha256:b68349e3a014b90c5610bfb26b2ae36f3892d7b8cf25ee140c6c71c98d2fcf48'

case "${1:-up}" in
  up)
    # Same server flags as the full compose's maindb, including --timeout 30,
    # which closes idle client connections under the app.
    docker run -d --name stg-valkey -p 127.0.0.1:6479:6379 -v stg_valkey:/data \
      -e REDISCLI_AUTH="$VALKEY_PASSWORD" "$VALKEY_IMG" \
      valkey-server --appendonly yes --appendfilename onetime.aof --appendfsync everysec \
      --dbfilename onetime.rdb --save 157680000 1 --bind 0.0.0.0 --port 6379 \
      --requirepass "$VALKEY_PASSWORD" --databases 1 --timeout 30 --loglevel notice --rdbcompression yes
    docker run -d --name stg-rabbitmq -p 127.0.0.1:5772:5672 -p 127.0.0.1:15772:15672 \
      -v stg_rabbitmq:/var/lib/rabbitmq --hostname stg-rabbitmq \
      -e RABBITMQ_DEFAULT_USER="$RABBITMQ_USER" -e RABBITMQ_DEFAULT_PASS="$RABBITMQ_PASS" \
      -e RABBITMQ_DEFAULT_VHOST=/ "$RABBIT_IMG"
    docker run -d --name stg-postgres -p 127.0.0.1:5532:5432 -v stg_postgres:/var/lib/postgresql/data \
      -e POSTGRES_PASSWORD="$PG_SUPER_PASS" "$PG_IMG"
    docker run -d --name stg-mailpit -p 127.0.0.1:1125:1025 -p 127.0.0.1:8125:8025 "$MAILPIT_IMG"
    ;;
  down)
    docker rm -f stg-valkey stg-rabbitmq stg-postgres stg-mailpit 2> /dev/null || true
    docker volume rm stg_valkey stg_rabbitmq stg_postgres 2> /dev/null || true
    ;;
  *)
    echo "usage: $0 up|down" >&2
    exit 64
    ;;
esac
