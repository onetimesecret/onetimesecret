#!/usr/bin/env bash
#
# tools/ci/tests/ci-test.sh
#
# bin/ci's dispatch, its refusals outside a GitLab CI job, and the commands
# that can run against stand-ins: `docker` and `sysctl` stubs on PATH, and a
# stub lane runner through BIN_CI_LANE_RUNNER.
#
# WHAT THIS PROTECTS
#
# toolchain, prepare and the daemon start change the machine they run on
# (packages, mounts, cgroups, iptables, .bundle/config). The refusal outside
# a GitLab job is what keeps a contributor who types `bin/ci prepare` on a
# laptop from rewriting their checkout's Bundler config. `bin/ci lane` must
# pass the GitHub run-test-lane action's log profile to the runner, keep the
# job's services (LANES_NO_AUTOSTART=1), and exit with the lane's status.
#
# Every bin/ci call here runs with GITLAB_CI unset unless the case sets it,
# because this suite itself runs in a GitLab job (shell-tests), where a call
# that inherited GITLAB_CI=true could reach apt or mount.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../../.." && pwd)"
# assert.sh is linted with tools/testsuite/, in another shellcheck run of the
# strict tier, so this run cannot follow it.
# shellcheck source=tools/testsuite/lib/assert.sh disable=SC1091
source "${REPO_ROOT}/tools/testsuite/lib/assert.sh"

BIN_CI="${REPO_ROOT}/bin/ci"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
STUBS="${WORK}/stubs"
CALLS="${WORK}/calls.log"
mkdir -p "$STUBS"

printf '%s\n' "$ASSERT_SUITE"

# docker: `info` answers when STUB_DOCKER_INFO=ok; every other call is
# logged and exits with STUB_DOCKER_STATUS (0 by default).
cat > "${STUBS}/docker" << 'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = info ]; then
  [ "${STUB_DOCKER_INFO:-down}" = ok ]
  exit
fi
printf 'docker %s\n' "$*" >> "$STUB_CALLS"
exit "${STUB_DOCKER_STATUS:-0}"
STUB
for name in sysctl dockerd apt-get mount; do
  cat > "${STUBS}/${name}" << STUB
#!/usr/bin/env bash
printf '${name} %s\n' "\$*" >> "\$STUB_CALLS"
STUB
done
# The lane runner: records its arguments and the variables bin/ci lane sets.
cat > "${STUBS}/lane-runner" << 'STUB'
#!/usr/bin/env bash
printf 'runner %s\n' "$*" >> "$STUB_CALLS"
printf 'LANES_NO_AUTOSTART=%s RSPEC_OUTPUT_FILE=%s GEM_HOME=%s\n' \
  "${LANES_NO_AUTOSTART:-}" "${RSPEC_OUTPUT_FILE:-}" "${GEM_HOME-unset}" >> "$STUB_CALLS"
exit "${STUB_LANE_STATUS:-0}"
STUB
chmod +x "${STUBS}"/*

# run <env assignments...> -- <bin/ci arguments...>: bin/ci with the stubs
# first on PATH and GITLAB_CI unset. Sets OUT (stdout and stderr), RC and
# CALLED (what the stubs recorded).
run() {
  local -a assignments=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
    assignments+=("$1")
    shift
  done
  shift
  : > "$CALLS"
  OUT="$(env -u GITLAB_CI -u DOCKER_HOST PATH="${STUBS}:${PATH}" STUB_CALLS="$CALLS" \
    ${assignments[@]+"${assignments[@]}"} bash "$BIN_CI" "$@" 2>&1)"
  RC=$?
  CALLED="$(cat "$CALLS")"
}

protects "bin/ci dispatch: help, and usage errors exit 64"
run -- --help
assert_eq "--help exits 0" 0 "$RC"
for command in toolchain 'docker up' 'services up' prepare 'lane <lane>'; do
  assert_contains "--help lists ${command}" "bin/ci ${command}" "$OUT"
done
run --
assert_eq "no command exits 64" 64 "$RC"
run -- deploy
assert_eq "an unknown command exits 64" 64 "$RC"
assert_contains "an unknown command is named" "unknown command: deploy" "$OUT"
run -- docker
assert_eq "docker without up exits 64" 64 "$RC"
run -- services up
assert_eq "services up without a service exits 64" 64 "$RC"
run -- lane
assert_eq "lane without a lane exits 64" 64 "$RC"
run -- lane smoke unit
assert_eq "lane with two lanes exits 64" 64 "$RC"
run -- lane ../smoke
assert_eq "lane refuses a path" 64 "$RC"

protects "toolchain and prepare refuse to run outside a GitLab CI job"
for command in toolchain prepare; do
  run -- "$command"
  assert_eq "${command} outside GitLab CI exits 1" 1 "$RC"
  assert_contains "${command} says why" "runs only in a GitLab CI job" "$OUT"
  assert_eq "${command} reached no apt-get or mount" "" "$CALLED"
done

protects "docker up does nothing when a daemon answers, and starts none outside a GitLab CI job"
run STUB_DOCKER_INFO=ok -- docker up
assert_eq "docker up with a daemon exits 0" 0 "$RC"
assert_contains "docker up says there is nothing to start" "nothing to start" "$OUT"
assert_eq "docker up with a daemon calls nothing else" "" "$CALLED"
run -- docker up
assert_eq "docker up with no daemon, outside GitLab CI, exits 1" 1 "$RC"
assert_contains "docker up says why" "runs only in a GitLab CI job" "$OUT"
assert_eq "docker up touched no mount, iptables or dockerd" "" "$CALLED"

protects "services up runs compose on compose.test.yml, and sets overcommit only in a GitLab job"
run STUB_DOCKER_INFO=ok -- services up valkey rabbitmq
assert_eq "services up exits 0" 0 "$RC"
assert_contains "services up starts the named services" \
  "docker compose -f ${REPO_ROOT}/compose.test.yml up --wait -d valkey rabbitmq" "$CALLED"
assert_not_contains "services up outside GitLab CI leaves sysctl alone" "sysctl" "$CALLED"
run GITLAB_CI=true STUB_DOCKER_INFO=ok -- services up valkey
assert_contains "services up in a GitLab job sets vm.overcommit_memory" \
  "sysctl -w vm.overcommit_memory=1" "$CALLED"
run STUB_DOCKER_STATUS=1 -- services up valkey
assert_eq "a failed bring-up exits 1" 1 "$RC"
assert_contains "a failed bring-up names the services" "compose did not bring up: valkey" "$OUT"

protects "lane: the CI log profile, the job's services, the lane's exit status"
run BIN_CI_LANE_RUNNER="${STUBS}/lane-runner" GEM_HOME=/usr/local/bundle -- lane smoke
assert_eq "a green lane exits 0" 0 "$RC"
assert_contains "the runner gets the lane and the capture profile" \
  "runner smoke --capture-logs --log-console off --quiet" "$CALLED"
assert_contains "the runner leaves the services to the job, writes results under tmp/, sees no GEM_HOME" \
  "LANES_NO_AUTOSTART=1 RSPEC_OUTPUT_FILE=tmp/rspec_smoke_results.json GEM_HOME=unset" "$CALLED"
run BIN_CI_LANE_RUNNER="${STUBS}/lane-runner" -- lane full-pg
assert_contains "a hyphenated lane gets an underscored results stem" \
  "RSPEC_OUTPUT_FILE=tmp/rspec_full_pg_results.json" "$CALLED"
run BIN_CI_LANE_RUNNER="${STUBS}/lane-runner" STUB_LANE_STATUS=3 -- lane smoke
assert_eq "a red lane's status is bin/ci lane's" 3 "$RC"
assert_contains "a red lane is reported" "bin/ci lane smoke: exit 3" "$OUT"

finish
