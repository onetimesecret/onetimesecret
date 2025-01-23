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

# Stop at the first sign of trouble
set -e

# Set PORT to the existing value or default to 3000
PORT=${PORT:-3000}

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

# Leave nothing but footprints
unset datestamp location basename

# Run bundler again so that new dependencies added to the
# Gemfile are installed at up time (i.e. avoids a rebuild).
# Check if BUNDLE_INSTALL is set to "true" (case-insensitive)
if [[ "${BUNDLE_INSTALL,,}" == "true" ]]; then
  >&2 echo "Running bundle install..."
  >&2 bundle install
else
  >&2 echo "Skipping bundle install. Use BUNDLE_INSTALL=true to run it."
fi

if [ -d "/mnt/public" ]; then
  # By default the static web assets are available at /mnt/public/web
  # in the container and /var/www/public on the host.
  cp -r public/web /mnt/public/
fi

# Run the command configured for the docker compose service
# in the docker-compose.yaml file, or a default if none is
# provided. See Dockerfile for more details.
if [ -z "$@" ]; then
  PORT="${PORT:-3000}" # explicit default
  exec bundle exec thin -R config.ru -p $PORT start
else
  exec bundle exec "$@"
fi
