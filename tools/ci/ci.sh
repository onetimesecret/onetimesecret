#!/usr/bin/env bash
#
# tools/ci/ci.sh — command dispatch for bin/ci (ADR-042).
#
# Usage:
#   bin/ci toolchain              install the tools a lane job needs (GitLab CI only)
#   bin/ci docker up              start a Docker daemon in the job unless one answers
#   bin/ci services up <name>...  start test services from compose.test.yml
#   bin/ci prepare                etc/ from etc/defaults, bundle and pnpm installs (GitLab CI only)
#   bin/ci lane <lane>            run tests/lanes/run <lane> with the CI log profile
#
# See tools/ci/README.md.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { sed -n '5,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

command="${1:-}"
[[ $# -gt 0 ]] && shift

case "$command" in
  toolchain) exec "${BASH:-bash}" "${HERE}/toolchain.sh" "$@" ;;
  docker) exec "${BASH:-bash}" "${HERE}/docker.sh" "$@" ;;
  services) exec "${BASH:-bash}" "${HERE}/services.sh" "$@" ;;
  prepare) exec "${BASH:-bash}" "${HERE}/prepare.sh" "$@" ;;
  lane) exec "${BASH:-bash}" "${HERE}/lane.sh" "$@" ;;
  -h | --help | help) usage ;;
  "")
    usage >&2
    exit 64
    ;;
  *)
    echo "bin/ci: unknown command: ${command}" >&2
    usage >&2
    exit 64
    ;;
esac
