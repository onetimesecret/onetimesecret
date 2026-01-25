#!/bin/bash
#
# Build with S6 Overlay (Multi-Process Supervision)
#
# Usage:
#   ./docker/s6/build.sh [docker build options]
#
# Examples:
#   ./docker/s6/build.sh                      # Build for current platform
#   ./docker/s6/build.sh --platform linux/amd64,linux/arm64
#   ./docker/s6/build.sh --no-cache
#
# This script builds using the main Dockerfile's final-s6 target.
# Includes S6 overlay for process supervision, running web + scheduler + worker
# in a single container with automatic crash recovery.

set -e

# Change to repository root (two directories up from this script)
cd "$(dirname "$0")/../.."

# Default tag
TAG="${TAG:-onetimesecret:s6}"

echo "Building with S6 overlay (multi-process supervision)..."
echo "Target: final-s6"
echo "Tag: $TAG"
echo ""

# Build with final-s6 target, forwarding all arguments
docker build \
  --target final-s6 \
  -t "$TAG" \
  "$@" \
  .

echo ""
echo "✓ Build complete: $TAG"
echo ""
echo "Run with:"
echo "  docker run -p 3000:3000 -e REDIS_URL=redis://redis:6379/0 -e SECRET=\$(openssl rand -hex 32) $TAG"
