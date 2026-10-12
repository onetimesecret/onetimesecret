#!/usr/bin/env bash
# Public command dispatch for bin/testsuite.
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TOOL_DIR/../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage: bin/testsuite <command> [arguments]

Commands:
  run [filter]                 Offline shell suites (default); filter by filename
  logtide [pytest arguments]   LogTide shipper tests in the locked uv environment
  caddy [unittest arguments]  Real-Caddy log redaction check (requires Caddy)
  verify-sentry-build [--quick]
                              Build/source-map checks; --quick uses existing output
  --help                      Show this help

The run command needs Bash 4+, Python 3 and jq, but no services or uv.
Python commands need uv and Python 3.11+; uv installs locked dependencies.
The Caddy check needs the transform-encoder plugin.
The Sentry build check needs jq and the repository's Node/pnpm dependencies.
USAGE
}

command="${1:-run}"
if [ "$#" -gt 0 ]; then shift; fi
case "$command" in
  run)
    exec "${BASH:-bash}" "$TOOL_DIR/run.sh" "$@"
    ;;
  logtide | caddy)
    command -v uv > /dev/null 2>&1 || {
      printf 'bin/testsuite %s needs uv: https://docs.astral.sh/uv/getting-started/installation/\n' "$command" >&2
      exit 69
    }
    if [ "$command" = logtide ]; then
      exec uv run --locked --directory "$TOOL_DIR" python -m pytest "$TOOL_DIR/test_logtide_ship.py" "$@"
    fi
    exec uv run --locked --directory "$TOOL_DIR" python "$TOOL_DIR/test_caddy_log_redaction.py" "$@"
    ;;
  verify-sentry-build)
    cd "$ROOT"
    exec "${BASH:-bash}" "$TOOL_DIR/verify-sentry-build.sh" "$@"
    ;;
  -h | --help | help)
    usage
    ;;
  *)
    printf 'Unknown testsuite command: %s\n' "$command" >&2
    usage >&2
    exit 64
    ;;
esac
