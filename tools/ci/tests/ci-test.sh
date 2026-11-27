#!/usr/bin/env bash
#
# tools/ci/tests/ci-test.sh
#
# bin/ci's dispatch, its refusals outside a GitLab CI job, and the commands
# that can run against stand-ins: `docker`, `sysctl`, `gem`, `bundle` and
# `pnpm` stubs on PATH, and a stub lane runner through BIN_CI_LANE_RUNNER.
#
# WHAT THIS PROTECTS
#
# toolchain, prepare and the daemon start change the machine they run on
# (packages, mounts, cgroups, iptables, .bundle/config). The refusal outside
# a GitLab job is what keeps a contributor who types `bin/ci prepare` on a
# laptop from rewriting their checkout's Bundler config. `bin/ci lane` must
# pass the GitHub run-test-lane action's log profile to the runner, keep the
# job's services (LANES_NO_AUTOSTART=1), and exit with the lane's status. An
# overlay must reach the runner and the results file name: without the first
# a billing row runs with billing off and passes, and without the second it
# overwrites the results of the row it repeats. `bin/ci rubocop` must fail
# on warnings and must not read the Ruby image's Bundler config, where the
# gems `bin/ci prepare bundle` installed are not recorded. `bin/ci prepare`
# with step names must run those steps only: the RuboCop job has no pnpm and
# the frontend build restores no gems.
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
for name in sysctl dockerd apt-get mount gem pnpm; do
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
# bundle: records its arguments and the two variables the Ruby image sets.
cat > "${STUBS}/bundle" << 'STUB'
#!/usr/bin/env bash
printf 'bundle %s\n' "$*" >> "$STUB_CALLS"
printf 'GEM_HOME=%s BUNDLE_APP_CONFIG=%s\n' "${GEM_HOME-unset}" "${BUNDLE_APP_CONFIG-unset}" >> "$STUB_CALLS"
exit "${STUB_BUNDLE_STATUS:-0}"
STUB
# nproc: prepare's bundle step asks for the job count; macOS has no nproc.
printf '#!/usr/bin/env bash\necho 2\n' > "${STUBS}/nproc"
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
for command in toolchain 'docker up' 'services up' prepare 'lane <lane> [<overlay>]' rubocop; do
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
run -- lane full-pg billing extra
assert_eq "lane with a third argument exits 64" 64 "$RC"
run -- lane ../smoke
assert_eq "lane refuses a path" 64 "$RC"
run -- lane full-pg ../billing
assert_eq "lane refuses a path as the overlay" 64 "$RC"
run -- lane full-pg --only
assert_eq "lane refuses a flag as the overlay" 64 "$RC"
run -- prepare gems
assert_eq "prepare with an unknown step exits 64" 64 "$RC"
assert_contains "the unknown step is named" "not a step: gems" "$OUT"
run -- rubocop lib
assert_eq "rubocop with an argument exits 64" 64 "$RC"

protects "toolchain and prepare refuse to run outside a GitLab CI job"
for command in toolchain prepare 'prepare checkout' 'prepare bundle' 'prepare pnpm'; do
  # shellcheck disable=SC2086 # two words on purpose: the command and its step
  run -- $command
  assert_eq "${command} outside GitLab CI exits 1" 1 "$RC"
  assert_contains "${command} says why" "runs only in a GitLab CI job" "$OUT"
  assert_eq "${command} reached no apt-get, mount or bundle" "" "$CALLED"
done

protects "prepare checkout: the checkout root and the directories above it lose group and other write"
# A stand-in for /builds/<group>/<project> under GitLab's umask 0000, with a
# sticky directory in the path. BIN_CI_CHECKOUT_STOP keeps the walk inside
# it; in a job the walk goes up to the filesystem root.
TREE="${WORK}/tree"
mkdir -p "${TREE}/builds/sticky/group/project"
chmod 0777 "$TREE" "${TREE}/builds" "${TREE}/builds/sticky/group" "${TREE}/builds/sticky/group/project"
chmod 1777 "${TREE}/builds/sticky"
modes() {
  local dir
  for dir in "$TREE" "${TREE}/builds" "${TREE}/builds/sticky" "${TREE}/builds/sticky/group" \
    "${TREE}/builds/sticky/group/project"; do
    # shellcheck disable=SC2012 # the mode column of one known directory
    printf '%s %s\n' "$(ls -ld "$dir" | awk '{ print substr($1, 1, 10) }')" "${dir#"$WORK"/}"
  done
}
loose="$(modes)"
run BIN_CI_CHECKOUT_ROOT="${TREE}/builds/sticky/group/project" BIN_CI_CHECKOUT_STOP="$TREE" -- prepare checkout
assert_eq "prepare checkout outside GitLab CI exits 1" 1 "$RC"
assert_eq "prepare checkout outside GitLab CI changes no mode" "$loose" "$(modes)"
run GITLAB_CI=true BIN_CI_CHECKOUT_ROOT="${TREE}/builds/sticky/group/project" BIN_CI_CHECKOUT_STOP="$TREE" \
  -- prepare bundle
assert_eq "prepare bundle changes no mode" "$loose" "$(modes)"
run GITLAB_CI=true BIN_CI_CHECKOUT_ROOT="${TREE}/builds/sticky/group/project" BIN_CI_CHECKOUT_STOP="$TREE" \
  -- prepare checkout
assert_eq "prepare checkout exits 0" 0 "$RC"
assert_eq "every owned, non-sticky directory up to the stop loses group and other write" "\
drwxrwxrwx tree
drwxr-xr-x tree/builds
drwxrwxrwt tree/builds/sticky
drwxr-xr-x tree/builds/sticky/group
drwxr-xr-x tree/builds/sticky/group/project" "$(modes)"
assert_contains "prepare checkout reports the mode before and after" \
  "drwxrwxrwx $(id -un) -> drwxr-xr-x $(id -un) ${TREE}/builds/sticky/group/project" "$OUT"
assert_eq "the checkout step runs first when prepare is given no step" \
  '[ "$#" -gt 0 ] || set -- checkout etc bundle pnpm' \
  "$(grep -F 'set -- ' "${REPO_ROOT}/tools/ci/prepare.sh")"

protects "prepare with step names runs those steps only, in the order given"
# Only `bundle` and `pnpm` run here, against the stubs. `checkout` and `etc`
# act on the real checkout this suite runs from (directory modes, etc/), and
# so does `prepare` with no step; those run in a GitLab job only.
run GITLAB_CI=true GEM_HOME=/usr/local/bundle BUNDLE_APP_CONFIG=/usr/local/bundle -- prepare bundle
assert_eq "prepare bundle exits 0" 0 "$RC"
assert_contains "prepare bundle installs the lockfile's Bundler" "gem install bundler -v " "$CALLED"
assert_contains "prepare bundle sets deployment mode in the checkout" \
  "bundle config set --local deployment true" "$CALLED"
assert_contains "prepare bundle installs into vendor/bundle" \
  "bundle config set --local path vendor/bundle" "$CALLED"
assert_contains "prepare bundle installs the gems" "bundle install --jobs 2" "$CALLED"
assert_contains "prepare bundle sees neither of the Ruby image's Bundler variables" \
  "GEM_HOME=unset BUNDLE_APP_CONFIG=unset" "$CALLED"
assert_not_contains "prepare bundle runs no pnpm" "pnpm" "$CALLED"
run GITLAB_CI=true -- prepare pnpm
assert_eq "prepare pnpm exits 0" 0 "$RC"
assert_eq "prepare pnpm runs the frozen install and nothing else" "pnpm install --frozen-lockfile" "$CALLED"
run GITLAB_CI=true -- prepare pnpm bundle
assert_matches "prepare pnpm bundle runs pnpm before the bundle" \
  '^pnpm install --frozen-lockfile.gem install bundler' "$(printf '%s' "$CALLED" | tr '\n' ' ')"

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

protects "lane with an overlay: the runner gets it, and the results file is the pair's own"
run BIN_CI_LANE_RUNNER="${STUBS}/lane-runner" -- lane full-pg billing
assert_eq "a green lane with an overlay exits 0" 0 "$RC"
assert_contains "the runner gets the overlay after the capture profile" \
  "runner full-pg --capture-logs --log-console off --quiet --overlay billing" "$CALLED"
assert_contains "the results stem names the lane and the overlay" \
  "RSPEC_OUTPUT_FILE=tmp/rspec_full_pg_billing_results.json" "$CALLED"
assert_contains "the overlay is in the report line" "bin/ci lane full-pg (overlay billing): exit 0" "$OUT"
run BIN_CI_LANE_RUNNER="${STUBS}/lane-runner" -- lane full-pg ''
assert_contains "an empty overlay argument is no overlay" \
  "runner full-pg --capture-logs --log-console off --quiet" "$CALLED"
assert_not_contains "an empty overlay argument passes no --overlay" "--overlay" "$CALLED"
assert_contains "an empty overlay argument keeps the lane's results stem" \
  "RSPEC_OUTPUT_FILE=tmp/rspec_full_pg_results.json" "$CALLED"

protects "rubocop: ci.yml's ruby-lint options, the checkout's Bundler config, RuboCop's exit status"
run GEM_HOME=/usr/local/bundle BUNDLE_APP_CONFIG=/usr/local/bundle -- rubocop
assert_eq "a clean tree exits 0" 0 "$RC"
assert_contains "rubocop runs through the bundle with the ruby-lint options" \
  "bundle exec rubocop --config .rubocop.yml --format progress --format json --out tmp/rubocop_results.json --fail-level warning" "$CALLED"
assert_contains "rubocop sees neither of the Ruby image's Bundler variables" \
  "GEM_HOME=unset BUNDLE_APP_CONFIG=unset" "$CALLED"
run STUB_BUNDLE_STATUS=1 -- rubocop
assert_eq "offenses fail the command with RuboCop's status" 1 "$RC"

finish
