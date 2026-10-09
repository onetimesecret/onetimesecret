#!/usr/bin/env bash
# Public command dispatch for bin/testsuite-installer.
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TOOL_DIR/../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage: bin/testsuite-installer <command> [arguments]

Commands:
  run [--lane baremetal|posix|ruby-old|all]
                              Clean-room installer matrix (requires Docker)
  baremetal-boot               Build and boot with a throwaway datastore under LANG=C
  secret-rotation             Verify rotation recovery with a throwaway app/datastore
  proof-of-life <base-url>     Check status, assets and the secret create/reveal loop
  proof-of-life --print-script Emit the standalone smoke script for container stdin
  check-docs-commands          Check documented entry points and pnpm targets
  seed-compose-env            Write throwaway Compose secrets to .env and GITHUB_ENV
  ttfhw-chart                 Chart fresh-clone durations (requires gh and jq)
  --help                      Show this help

Install/boot commands have side effects; no command runs by default.
See tools/testsuite-installer/README.md for prerequisites and environment knobs.
USAGE
}

command="${1:-}"
if [ "$#" -gt 0 ]; then shift; fi
case "$command" in
  proof-of-life)
    if [ "${1:-}" = --print-script ]; then
      if [ "$#" -ne 1 ]; then
        printf 'Usage: bin/testsuite-installer proof-of-life --print-script\n' >&2
        exit 64
      fi
      exec cat "$TOOL_DIR/proof-of-life.sh"
    fi
    ;;
  run | baremetal-boot | secret-rotation | check-docs-commands | seed-compose-env | ttfhw-chart)
    ;;
  -h | --help | help)
    usage
    exit 0
    ;;
  '')
    usage >&2
    exit 64
    ;;
  *)
    printf 'Unknown testsuite-installer command: %s\n' "$command" >&2
    usage >&2
    exit 64
    ;;
esac

cd "$ROOT"
exec "${BASH:-bash}" "$TOOL_DIR/$command.sh" "$@"
