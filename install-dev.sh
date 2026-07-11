#!/usr/bin/env bash

# install-dev.sh — deprecated entry point, kept as a delegate.
#
# The canonical setup command is now:
#
#   bin/setup
#
# Same behavior (dev environment: deps, config, secrets, git hooks), one
# name. This shim will be removed after a deprecation window.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Note: install-dev.sh is deprecated — use 'bin/setup' (running it for you now)." >&2
exec "$ROOT/bin/setup" --dev
