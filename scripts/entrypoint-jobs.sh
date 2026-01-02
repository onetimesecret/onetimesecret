#!/bin/bash
#
# Start both the job scheduler and worker in a single container.
# Intended for staging/development environments.
#
# For production, run scheduler and worker as separate services
# for independent scaling and fault isolation.
#
# How it works:
#   1. Starts scheduler and worker as background processes
#   2. Captures their PIDs for signal forwarding using trap
#   3. Sets up trap to forward SIGTERM/SIGINT to both children
#   4. Waits for both to exit (container stays alive)
#
# On container stop (docker stop / k8s termination):
#   - Docker sends SIGTERM to PID 1 (this script)
#   - Trap forwards SIGTERM to scheduler and worker
#   - Both processes shut down gracefully
#   - Script exits when both children terminate
#

set -e

# Start scheduler in background, capture PID
bin/ots scheduler &
scheduler_pid=$!

# Start worker in background, capture PID
bin/ots worker &
worker_pid=$!

# Forward termination signals to both child processes
# trap catches SIGTERM/SIGINT and runs kill instead of dying immediately
# Without this, children would become orphans on container stop
trap "kill -TERM $scheduler_pid $worker_pid 2>/dev/null" SIGTERM SIGINT

# Block until both processes exit
wait $scheduler_pid $worker_pid
