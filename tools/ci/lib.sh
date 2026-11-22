# shellcheck shell=bash
#
# tools/ci/lib.sh — helpers shared by the bin/ci commands. Sourced.

CI_TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_REPO_ROOT="$(cd "${CI_TOOL_DIR}/../.." && pwd)"
# What a job keeps as artifacts besides the lane's own files: the daemon's
# log and the service logs of a failed run.
CI_OUT_DIR="${CI_REPO_ROOT}/tmp/ci"
COMPOSE_FILE_TEST="${CI_REPO_ROOT}/compose.test.yml"

ci_die() {
  printf 'bin/ci: %s\n' "$*" >&2
  exit 1
}

ci_usage_error() {
  printf 'bin/ci: %s\n' "$*" >&2
  exit 64
}

# toolchain, prepare and the daemon start change the machine they run on:
# system packages, mounts, cgroups, iptables and the checkout's
# .bundle/config. They run only in a GitLab CI job, whose container is
# discarded when the job ends.
ci_require_gitlab_job() { # <what>
  if [ "${GITLAB_CI:-}" != true ]; then
    ci_die "$1 changes the machine it runs on (packages, mounts, cgroups, .bundle/config), so it runs only in a GitLab CI job (GITLAB_CI=true)"
  fi
}

# Collapsible sections in a GitLab job log; a plain header elsewhere.
# https://docs.gitlab.com/ci/jobs/job_logs/#custom-collapsible-sections
ci_section_start() { # <id> <title>
  if [ "${GITLAB_CI:-}" = true ]; then
    printf '\033[0Ksection_start:%s:%s\r\033[0K%s\n' "$(date +%s)" "$1" "$2"
  else
    printf '\n== %s\n' "$2"
  fi
}

ci_section_end() { # <id>
  if [ "${GITLAB_CI:-}" = true ]; then
    printf '\033[0Ksection_end:%s:%s\r\033[0K\n' "$(date +%s)" "$1"
  fi
}

# The state and recent logs of the test services, on stderr and in
# tmp/ci/services.log. A job's daemon is gone by after_script, so a failed
# command calls this before it exits.
ci_dump_services() {
  docker info > /dev/null 2>&1 || return 0
  mkdir -p "$CI_OUT_DIR"
  {
    docker compose -f "$COMPOSE_FILE_TEST" ps -a
    docker compose -f "$COMPOSE_FILE_TEST" logs --no-color --timestamps
  } > "${CI_OUT_DIR}/services.log" 2>&1 || true
  docker compose -f "$COMPOSE_FILE_TEST" ps -a >&2 || true
  docker compose -f "$COMPOSE_FILE_TEST" logs --no-color --tail 40 >&2 || true
  printf 'bin/ci: full service logs in tmp/ci/services.log\n' >&2
}
