#!/usr/bin/env bash
#
# tools/host-seam/host-seam.sh — command dispatch for bin/host-seam (ADR-042).
#
# Usage:
#   bin/host-seam probe --base URL --canonical HOST --custom HOST [...]
#   bin/host-seam sweep TAG [TAG ...]
#   bin/host-seam <command> --help
#
# probe   send the topology matrix (topologies.psv) at one running app
# sweep   run the probe against a series of published release images
#
# See tools/host-seam/README.md.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

command="${1:-}"
[[ $# -gt 0 ]] && shift

case "$command" in
  probe) exec "${BASH:-bash}" "${HERE}/topology-probe.sh" "$@" ;;
  sweep) exec "${BASH:-bash}" "${HERE}/release-sweep.sh" "$@" ;;
  -h | --help | help) usage ;;
  "") usage >&2; exit 2 ;;
  *) echo "unknown command: ${command}" >&2; usage >&2; exit 2 ;;
esac
