#!/bin/sh

#
# ONETIME ENTRYPOINT SCRIPT - 2022-07-09
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
#

# Stop at the first sign of trouble
set -e

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
>&2 bundle install

# Run the command configured for the docker compose service
# in the docker-compose.yaml file.
exec bundle exec $@
