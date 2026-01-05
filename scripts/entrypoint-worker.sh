#!/bin/bash
#
# Start a worker in a single container.
# Intended for staging/development environments.
#
# How it works:
#   1. Starts scheduler and worker as background processes
#   2. Captures their PIDs for signal forwarding using trap
#   3. Sets up trap to forward SIGTERM/SIGINT to both children
#   4. Waits for both to exit (container stays alive)
#
# On container stop (podman stop / k8s termination):
#   - Podman sends SIGTERM to PID 1 (this script)
#   - Trap forwards SIGTERM to worker
#   - Worker process shuts down gracefully
#   - Script exits when children process terminates
#

set -e

# Start worker in background, capture PID
bin/ots worker &
worker_pid=$!

# Forward termination signals to child processes trap catches
# SIGTERM/SIGINT and runs kill instead of dying immediately.
# Without this, children would become orphans on container stop.
trap "kill -TERM $worker_pid 2>/dev/null" SIGTERM SIGINT

# Block until both processes exit
wait $worker_pid
