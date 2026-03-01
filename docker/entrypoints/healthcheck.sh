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
  local hostport
  if [[ "$clean" == *@* ]]; then
    hostport="${clean#*@}"
  else
    hostport="$clean"
  fi

  AMQP_HOST="${hostport%%:*}"
  AMQP_PORT="${hostport#*:}"
  AMQP_PORT="${AMQP_PORT%%/*}"  # strip /vhost suffix
  AMQP_PORT="${AMQP_PORT:-5672}"
}

# Web server: puma listens on $PORT (default 3000)
# Try /health/advanced first (verifies Redis + RabbitMQ + auth DB),
# fall back to /health (lightweight status-only check).
if pgrep -f 'puma' > /dev/null 2>&1; then
  base="http://127.0.0.1:${PORT:-3000}"
  curl -sf "${base}/health/advanced" | grep -q '"status":"ok"' && exit 0
  exec curl -sf "${base}/health"
fi

# Worker or scheduler: verify TCP connectivity to RabbitMQ.
if pgrep -f 'bin/ots' > /dev/null 2>&1; then
  parse_amqp_addr
  timeout 5 bash -c "echo > /dev/tcp/${AMQP_HOST}/${AMQP_PORT}" 2>/dev/null
  exit $?
fi

# No recognized process found
exit 1
