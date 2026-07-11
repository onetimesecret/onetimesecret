#!/usr/bin/env bash

# install-test.sh — deprecated entry point, kept as a delegate.
#
# The canonical setup command is now:
#
#   bin/setup --test
#
# Same behavior (test lane: throwaway datastore on :2121, .test-mode marker,
# config smoke test), one name. This shim will be removed after a
# deprecation window.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Note: install-test.sh is deprecated — use 'bin/setup --test' (running it for you now)." >&2
exec "$ROOT/bin/setup" --test
