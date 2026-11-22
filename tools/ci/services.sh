#!/usr/bin/env bash
#
# tools/ci/services.sh — bin/ci services up <service>...: start test services
# from compose.test.yml, the file that defines their images and 127.0.0.1
# ports for every lane run (tests/lanes/README.md). Same command as the
# GitHub jobs' "Start test services" step.
#
# In a GitLab CI job it first sets vm.overcommit_memory=1 for Valkey, as the
# setup-ruby-test-env action does on GitHub. A failed bring-up prints the
# services' state and logs before it exits.
set -euo pipefail

# shellcheck source=tools/ci/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage="usage: bin/ci services up <service>... (names from compose.test.yml)"
case "${1:-}" in
  up) shift ;;
  *) ci_usage_error "$usage" ;;
esac
[ "$#" -gt 0 ] || ci_usage_error "$usage"

if [ "${GITLAB_CI:-}" = true ]; then
  sysctl -w vm.overcommit_memory=1 ||
    printf 'bin/ci services up: could not set vm.overcommit_memory=1\n' >&2
fi

ci_section_start services_up "Start test services: $*"
started=$SECONDS
if ! docker compose -f "$COMPOSE_FILE_TEST" up --wait -d "$@"; then
  ci_dump_services
  ci_die "compose did not bring up: $*"
fi
docker compose -f "$COMPOSE_FILE_TEST" ps
ci_section_end services_up
printf 'bin/ci services up: %s ready in %ss\n' "$*" "$((SECONDS - started))"
