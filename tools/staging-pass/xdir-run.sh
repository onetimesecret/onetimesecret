#!/usr/bin/env bash
#
# tools/staging-pass/xdir-run.sh — the two-direction test in full mode.
#
# The earlier release (published image) and the working tree take turns on
# the same Valkey, auth database, RabbitMQ and mail sink, behind the same
# proxy: the earlier release writes and the working tree reads (upgrade),
# then the working tree writes on that data and the earlier release reads
# (rollback).
#
#   tools/staging-pass/xdir-run.sh sqlite|pg
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${STAGING_ROOT:-/srv/ots-staging}
STATE=${STAGING_STATE:-$ROOT/state}
set -a
# shellcheck disable=SC1091
. "$STATE/secrets.env"
set +a
db=${1:-sqlite}
cd "$here/tests" || exit 1

"$here/stack.sh" down head
"$here/stack.sh" down v19
if [ "$db" = pg ]; then
  cat > "$ROOT/override.env" << ENV
AUTH_DATABASE_URL=postgresql://ots_user:$PG_USER_PASS@127.0.0.1:5532/onetime_authdb
AUTH_DATABASE_URL_MIGRATIONS=postgresql://ots_migrator:$PG_MIGRATOR_PASS@127.0.0.1:5532/onetime_authdb
ENV
else
  rm -f "$ROOT/override.env"
fi
"$here/stack.sh" reset
: > "$ROOT/logs/head-web.log"
: > "$ROOT/logs/head-worker.log"
: > "$ROOT/logs/head-scheduler.log"

echo "### $db: earlier release writes"
"$here/stack.sh" up v19 || exit 1
python3 xdir_write.py "$db-v19-to-head" v19 | grep -E "FAIL|^=="
"$here/stack.sh" down v19
echo "### $db: working tree reads (upgrade)"
"$here/stack.sh" up head web || exit 1
python3 xdir_read.py "$db-v19-to-head" head | grep -E "FAIL|NOTE|^=="

echo "### $db: working tree writes (on the upgraded data)"
"$here/stack.sh" down head worker scheduler
"$here/stack.sh" up head worker scheduler
python3 xdir_write.py "$db-head-to-v19" head | grep -E "FAIL|^=="
"$here/stack.sh" down head
echo "### $db: earlier release reads (rollback)"
"$here/stack.sh" up v19 web || exit 1
python3 xdir_read.py "$db-head-to-v19" v19 | grep -E "FAIL|NOTE|^=="
"$here/stack.sh" down v19

head_errors=$(grep -a -c 'Unhandled error' "$ROOT/logs/head-web.log")
v19_errors=$(cat "$ROOT"/logs/v19-*.log 2> /dev/null | grep -a -c 'Unhandled error')
echo "### unhandled errors: working tree web log $head_errors; earlier release logs $v19_errors"
