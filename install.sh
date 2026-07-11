#!/usr/bin/env bash

# install.sh — deprecated entry point, kept as a delegate.
#
# The canonical setup command is now bin/setup:
#
#   ./install.sh              ->  bin/setup --init       (auto-reconciles)
#   ./install.sh init         ->  bin/setup --init
#   ./install.sh reconcile    ->  bin/setup --reconcile
#   ./install.sh doctor       ->  bin/setup --doctor
#   ./install.sh console      ->  bin/setup --console
#
# This shim will be removed after a deprecation window.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cmd="${1:-init}"
case "$cmd" in
  auto|init|reconcile|console|doctor|help|-h|--help)
    echo "Note: install.sh is deprecated — use 'bin/setup' (running 'bin/setup ${cmd#--}' for you now)." >&2
    exec "$ROOT/bin/setup" "$cmd"
    ;;
  *)
    "$ROOT/bin/setup" --help >&2
    echo "Unknown command: $cmd" >&2
    exit 1
    ;;
esac
