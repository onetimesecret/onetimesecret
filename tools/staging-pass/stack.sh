#!/usr/bin/env bash
#
# tools/staging-pass/stack.sh — start or stop one version's processes on
# the shared staging datastores.
#
#   stack.sh up|down head|v19 [web|worker|scheduler ...]
#   stack.sh reset     flush Valkey, the queues, the auth database, the mail sink
#   stack.sh status
#
# `head` is the working tree's install, run natively as uid 1001. `v19` is
# the published image of the earlier release (BASELINE_IMAGE), run with host
# networking so both versions reach the same services on the same addresses.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${STAGING_ROOT:-/srv/ots-staging}
STATE=${STAGING_STATE:-$ROOT/state}
set -a
# shellcheck disable=SC1091
. "$STATE/secrets.env"
set +a
IMG=${BASELINE_IMAGE:-onetimesecret/onetimesecret:v0.26.19}
RABBIT=http://127.0.0.1:15772/api

valkey() { redis-cli -p 6479 -a "$VALKEY_PASSWORD" --no-auth-warning "$@"; }

wait_http() {
  for _ in $(seq 1 90); do
    curl -s --noproxy '*' -o /dev/null -m 2 http://127.0.0.1:3000/api/v2/status && return 0
    sleep 1
  done
  echo "web did not come up" >&2
  return 1
}

up_head() {
  local p
  for p in "$@"; do
    (setsid runuser -u appuser -- "$here/run-head.sh" "$p" >> "$ROOT/logs/head-$p.log" 2>&1 &)
    if [ "$p" = web ]; then wait_http || return 1; fi
  done
}

down_head() {
  local p f pid
  for p in "$@"; do
    f=$ROOT/logs/head-$p.pid
    [ -f "$f" ] || continue
    pid=$(cat "$f")
    kill -TERM "$pid" 2> /dev/null
    for _ in $(seq 1 40); do
      kill -0 "$pid" 2> /dev/null || break
      sleep 0.5
    done
    kill -KILL "$pid" 2> /dev/null
    rm -f "$f"
  done
}

v19_run() {
  local name=$1
  shift
  local envs=(--env-file "$ROOT/app.env")
  [ -f "$ROOT/override.env" ] && envs+=(--env-file "$ROOT/override.env")
  docker run -d --name "v19-$name" --network host "${envs[@]}" \
    -v "$ROOT/head/data:/app/data" -v "$ROOT/v19-etc/config.yaml:/app/etc/config.yaml:ro" "$IMG" "$@" > /dev/null
}

up_v19() {
  local p
  for p in "$@"; do
    case $p in
      web) v19_run web && wait_http || return 1 ;;
      worker) v19_run worker ./bin/ots worker --queues email.message.send --concurrency 5 --environment production ;;
      scheduler) v19_run scheduler ./bin/ots scheduler --environment production ;;
    esac
  done
}

down_v19() {
  local p
  for p in "$@"; do
    docker stop -t 20 "v19-$p" > /dev/null 2>&1
    docker logs "v19-$p" > "$ROOT/logs/v19-$p.$(date +%s).log" 2>&1
    docker rm -f "v19-$p" > /dev/null 2>&1
  done
}

cmd=${1:-status}
ver=${2:-}
shift 2 2> /dev/null || true
parts=("$@")
[ ${#parts[@]} -eq 0 ] && parts=(web worker scheduler)

case "$cmd" in
  up | down)
    case "$ver" in
      head | v19) "${cmd}_${ver}" "${parts[@]}" ;;
      *)
        echo "usage: $0 up|down head|v19 [web|worker|scheduler ...]" >&2
        exit 64
        ;;
    esac
    ;;
  reset)
    valkey flushall > /dev/null
    queues=$(curl -s --noproxy '*' -u "$RABBITMQ_USER:$RABBITMQ_PASS" "$RABBIT/queues/%2F" |
      python3 -c "import sys,json; [print(q['name']) for q in json.load(sys.stdin)]")
    for q in $queues; do
      curl -s --noproxy '*' -u "$RABBITMQ_USER:$RABBITMQ_PASS" -X DELETE "$RABBIT/queues/%2F/$q/contents" > /dev/null
    done
    rm -f "$ROOT/head/data/auth.db" "$ROOT/head/data/auth.db-wal" "$ROOT/head/data/auth.db-shm" \
      "$ROOT/head/data/auth.db-journal"
    PGPASSWORD=$PG_SUPER_PASS psql -h 127.0.0.1 -p 5532 -U postgres -q \
      -c "DROP DATABASE IF EXISTS onetime_authdb" -c "DROP ROLE IF EXISTS ots_user" \
      -c "DROP ROLE IF EXISTS ots_migrator" > /dev/null 2>&1
    PGPASSWORD=$PG_SUPER_PASS psql -h 127.0.0.1 -p 5532 -U postgres -q -v ON_ERROR_STOP=1 \
      -f "$STATE/pg-init.sql" > /dev/null 2>&1 || echo "pg init failed" >&2
    curl -s --noproxy '*' -X DELETE http://127.0.0.1:8125/api/v1/messages > /dev/null
    echo "reset: valkey dbsize=$(valkey dbsize)"
    ;;
  status)
    for p in web worker scheduler; do
      f=$ROOT/logs/head-$p.pid
      if [ -f "$f" ] && kill -0 "$(cat "$f")" 2> /dev/null; then echo "head $p: pid $(cat "$f")"; fi
    done
    docker ps --format '{{.Names}} {{.Status}}' | grep '^v19-' || true
    ;;
  *)
    echo "usage: $0 up|down|reset|status ..." >&2
    exit 64
    ;;
esac
