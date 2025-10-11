#!/bin/bash

##
# ONETIME ENTRYPOINT SCRIPT - 2024-05-18
#
#   Usage:
#
#     1. In docker-compose.yaml, add a command setting for
#       this docker service.
#
#       e.g.
#
#         service:
#           onetime:
#             extends: onetime-config
#        -->  command: ["onetime", "-h", "0.0.0.0", "-p", "3000"]
#
#   Server Options:
#
#     SERVER_TYPE=thin (default) - Use Thin server
#     SERVER_TYPE=puma          - Use Puma server
#
#   Puma Options:
#
#     PUMA_MIN_THREADS=4        - Minimum number of threads
#     PUMA_MAX_THREADS=16       - Maximum number of threads
#     PUMA_WORKERS=2            - Number of worker processes
#

# Stop at the first sign of trouble
set -e

# Enable immediate output for better debugging
export RUBY_UNBUFFERED=1
if [ "$STDOUT_SYNC" = "1" ] || [ "$ONETIME_DEBUG" = "1" ]; then
  # Force stdout/stderr to be unbuffered for real-time logging
  stdbuf -oL -eL bash -c 'exec "$@"' -- "$@" &
  wait $!
fi

# Set PORT to the existing value or default to 3000
PORT=${PORT:-3000}

# Set web server type to run
#
# One of: thin (default), puma
SERVER_TYPE=${SERVER_TYPE:-thin}

# Puma settings
PUMA_MIN_THREADS=${PUMA_MIN_THREADS:-4}
PUMA_MAX_THREADS=${PUMA_MAX_THREADS:-16}
PUMA_WORKERS=${PUMA_WORKERS:-2}

if [ "$ONETIME_DEBUG" = "true" ] || [ "$ONETIME_DEBUG" = "1" ]; then
  # Prints commands and their arguments as they are executed. This allows
  # for more verbose output, helping with debugging and troubleshooting.
  set -x
fi

# Get the time in UTC, with macos compatibility
datestamp=`date -u`

# Figure out who we are
location=$(readlink -f "${0}")
basename=$(basename "${location}")

# Drop a line in the build logs (including any error msgs)
>&2 echo "[${datestamp}] INFO: Running ${basename}..."

# Immediate environment debugging for Redis connection issues
if [ "$ONETIME_DEBUG" = "true" ] || [ "$ONETIME_DEBUG" = "1" ]; then
  >&2 echo "[${datestamp}] DEBUG: Environment variables:"
  >&2 echo "  REDIS_URL=${REDIS_URL:-<not set>}"
  >&2 echo "  VALKEY_URL=${VALKEY_URL:-<not set>}"
  >&2 echo "  SECRET=${SECRET:+<set>}"
  >&2 echo "  SERVER_TYPE=${SERVER_TYPE}"
  >&2 echo "  RACK_ENV=${RACK_ENV:-<not set>}"
fi

# Leave nothing but footprints
unset datestamp location basename

# Check for v0.23.0 migration requirement
# This migration is required for users with custom etc/config.yaml files
if [ -f "etc/config.yaml" ] && [ -f "migrate/20250727-1523_standardize_config_symbols_to_strings.rb" ]; then
  # Check if migration is needed by looking for symbol keys in config
  if grep -q "^[[:space:]]*:[a-zA-Z_][a-zA-Z0-9_]*:" etc/config.yaml 2>/dev/null; then
    cat >&2 <<EOF

===============================================================================
 MIGRATION REQUIRED - Onetime Secret v0.23.0
===============================================================================

Your custom config file (etc/config.yaml) needs to be updated for v0.23.0.

This migration converts YAML symbol keys (:key:) to string keys (key:).

TO RUN THE MIGRATION:

  1. Stop this container
  2. Run the migration:
     docker run --rm -v "\$(pwd)/etc:/app/etc" onetimesecret \\
       bin/ots migrate 20250727-1523_standardize_config_symbols_to_strings.rb --run
  3. Restart your container

FOR MORE HELP:
  - See the v0.23.0 release notes
  - Run migration with --dry-run to preview changes
  - Backup your config file before running migration

===============================================================================

EOF
    >&2 echo "ERROR: Migration required before starting. Container will exit in 10 seconds..."
    sleep 10
    exit 1
  fi
fi

# Run bundler again so that new dependencies added to the
# Gemfile are installed at up time (i.e. avoids a rebuild).
# Check if BUNDLE_INSTALL is set to "true" (case-insensitive)
if [[ "${BUNDLE_INSTALL,,}" == "true" ]]; then
  >&2 echo "INFO: Running bundle install..."
  >&2 bundle install
else
  >&2 echo "INFO: Skipping bundle install. Use BUNDLE_INSTALL=true to run it."
fi

if [ -d "/mnt/public" ]; then
  # By default the static web assets are available at /mnt/public/web
  # in the container and /var/www/public on the host.
  cp -r public/web /mnt/public/
fi

# Test Redis connectivity early to fail fast
if [ "$ONETIME_DEBUG" = "true" ] || [ "$ONETIME_DEBUG" = "1" ]; then
  >&2 echo "[${datestamp}] DEBUG: Testing Redis connectivity..."

  # Extract host and port from REDIS_URL or VALKEY_URL
  REDIS_TEST_URL="${VALKEY_URL:-${REDIS_URL:-redis://127.0.0.1:6379}}"

  # Simple connectivity test using basic tools
  if command -v nc >/dev/null 2>&1; then
    REDIS_HOST=$(echo "$REDIS_TEST_URL" | sed 's|redis://||' | cut -d'@' -f2 | cut -d':' -f1)
    REDIS_PORT=$(echo "$REDIS_TEST_URL" | sed 's|redis://||' | cut -d'@' -f2 | cut -d':' -f2 | cut -d'/' -f1)

    # Default to standard Redis port if parsing fails
    REDIS_HOST=${REDIS_HOST:-127.0.0.1}
    REDIS_PORT=${REDIS_PORT:-6379}

    >&2 echo "[${datestamp}] DEBUG: Testing connection to ${REDIS_HOST}:${REDIS_PORT}"

    if ! nc -zv "$REDIS_HOST" "$REDIS_PORT" 2>&1; then
      >&2 echo "[${datestamp}] WARNING: Cannot connect to Redis at ${REDIS_HOST}:${REDIS_PORT}"
      >&2 echo "[${datestamp}] WARNING: Application may fail to start"
    else
      >&2 echo "[${datestamp}] DEBUG: Redis connectivity test passed"
    fi
  else
    >&2 echo "[${datestamp}] DEBUG: nc not available, skipping connectivity test"
  fi
fi

# Run the command configured for the docker compose service
# in the docker-compose.yaml file, or a default if none is
# provided. See Dockerfile for more details.
#
# Check if no arguments were provided to the script
# (e.g. running container without command override).
if [ $# -eq 0 ]; then
  PORT="${PORT:-3000}" # explicit default

  # Choose server based on SERVER_TYPE environment variable
  if [ "$SERVER_TYPE" = "puma" ]; then
    >&2 echo "Starting Puma server on port $PORT with $PUMA_WORKERS workers ($PUMA_MIN_THREADS-$PUMA_MAX_THREADS threads)"
    # Enable real-time logging for Ruby applications
    RUBY_YJIT_ENABLE=1 RUBY_UNBUFFERED=1 exec stdbuf -oL -eL bundle exec puma -R config.ru -p $PORT -t $PUMA_MIN_THREADS:$PUMA_MAX_THREADS -w $PUMA_WORKERS
  else
    >&2 echo "Starting Thin server on port $PORT"
    # Enable real-time logging for Ruby applications
    RUBY_UNBUFFERED=1 exec stdbuf -oL -eL bundle exec thin -R config.ru -p $PORT start
  fi
else
  exec bundle exec "$@"
fi
