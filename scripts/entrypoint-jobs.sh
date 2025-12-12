#!/bin/bash
#
# Start both the job scheduler and worker in a single container.
# Intended for staging/development environments.
#
# For production, run scheduler and worker as separate services
# for independent scaling and fault isolation.
#

set -e

# Start scheduler in background
bin/ots jobs scheduler &

# Run worker in foreground (becomes PID 1 for signal handling)
exec bin/ots jobs worker
