#!/bin/bash
#
# Role-aware container healthcheck
#
# Detects whether this container is running as a web server, worker,
# or scheduler and applies the appropriate health check:
#
#   - Web (puma): HTTP check against /health or /health/advanced
#   - Worker/Scheduler: TCP connectivity to RabbitMQ
#
# This avoids false "unhealthy" status on worker/scheduler containers
# that don't listen on any port.
#

# Parse host and port from an AMQP URL.
# Handles: amqp://host:port, amqp://user:pass@host:port/vhost
parse_amqp_addr() {
  local url="${RABBITMQ_URL:-amqp://127.0.0.1:5672}"
  local clean="${url#amqp://}"

  # Strip auth credentials if present (user:pass@...)
  local authority
  if [[ "$clean" == *@* ]]; then
    authority="${clean#*@}"
  else
    authority="$clean"
  fi

  # Separate host:port from /vhost path before extracting components
  local hostport="${authority%%/*}"

  if [[ "$hostport" == *:* ]]; then
    AMQP_HOST="${hostport%%:*}"
    AMQP_PORT="${hostport#*:}"
  else
    AMQP_HOST="$hostport"
    AMQP_PORT=""
  fi

  AMQP_PORT="${AMQP_PORT:-5672}"
}

# Web server: puma listens on $PORT (default 3000)
# Check /health/advanced (verifies Redis + RabbitMQ + auth DB): healthy only
# if the TOP-LEVEL status is "ok" — a 200-but-degraded response is unhealthy.
# Fall back to /health (lightweight liveness) only when /health/advanced
# itself is unreachable or non-2xx (e.g. older images without the endpoint).
if pgrep -f 'puma' > /dev/null 2>&1; then
  base="http://127.0.0.1:${PORT:-3000}"
  if response=$(curl -sf "${base}/health/advanced"); then
    # ruby is guaranteed in the runtime image; jq is not
    printf '%s' "$response" | ruby -rjson -e 'exit(JSON.parse($stdin.read)["status"] == "ok" ? 0 : 1)' 2>/dev/null
    exit $?
  fi
  exec curl -sf "${base}/health"
fi

# Worker or scheduler: verify TCP connectivity to RabbitMQ.
if pgrep -f 'bin/ots' > /dev/null 2>&1; then
  parse_amqp_addr
  timeout 5 bash -c 'echo > "/dev/tcp/$1/$2"' -- "${AMQP_HOST}" "${AMQP_PORT}" 2>/dev/null
  exit $?
fi

# No recognized process found
echo "healthcheck: no puma or bin/ots process found" >&2
exit 1
