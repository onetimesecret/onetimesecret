#!/usr/bin/env bash
#
# tools/staging-pass/run-head.sh — run one process of the working tree's
# install the way the image runs it: the image's ENV, the install's env
# file, the commands docker-compose.full.yml gives each service. Meant to be
# started as uid 1001 (stack.sh does that).
#
#   run-head.sh web | worker | scheduler | ots <args...>
set -euo pipefail
ROOT=${STAGING_ROOT:-/srv/ots-staging}
cd "$ROOT/head"
set -a
# shellcheck disable=SC1091
. "$ROOT/app.env"
# shellcheck disable=SC1091
[ ! -f "$ROOT/override.env" ] || . "$ROOT/override.env"
set +a
ruby_bin=${STAGING_RUBY_BIN:-/opt/rbenv/versions/$(cat .ruby-version)/bin}
export HOME=$ROOT/home
export PATH=$ruby_bin:$ROOT/head/bin:/usr/local/bin:/usr/bin:/bin
export ONETIME_HOME=$ROOT/head RUBY_YJIT_ENABLE=1 RUBY_UNBUFFERED=1 SERVER_TYPE=puma
export BUNDLE_WITHOUT="development:test:optional"
# An outbound proxy configured for the shell is not part of an install.
unset HTTPS_PROXY https_proxy HTTP_PROXY http_proxy NO_PROXY no_proxy

case "${1:-web}" in
  web)
    echo $$ > "$ROOT/logs/head-web.pid"
    exec bundle exec puma -C etc/puma.rb
    ;;
  worker)
    echo $$ > "$ROOT/logs/head-worker.pid"
    exec ./bin/ots worker --queues email.message.send --concurrency 5 --environment production
    ;;
  scheduler)
    echo $$ > "$ROOT/logs/head-scheduler.pid"
    exec ./bin/ots scheduler --environment production
    ;;
  ots)
    shift
    exec ./bin/ots "$@"
    ;;
  *)
    exec "$@"
    ;;
esac
