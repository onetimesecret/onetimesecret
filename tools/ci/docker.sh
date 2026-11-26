#!/usr/bin/env bash
#
# tools/ci/docker.sh — bin/ci docker up: make a Docker daemon answer.
#
# When `docker info` already succeeds (a workstation, a GitHub runner, a
# self-hosted runner with its own daemon) this does nothing. Otherwise, in a
# GitLab CI job only, it starts dockerd inside the job container. The recipe
# is the one spike S1 ran on GitLab.com's hosted Linux runners
# (docs/planning/2026-1110-gitlab-ci-migration-plan.md, §7, "S1, first pass"):
#
#   - The data root is a directory under CI_BUILDS_DIR, outside the project
#     directory, so neither the checkout nor the job cache touches it. On the
#     container's overlay root filesystem the daemon either does not start or
#     cannot unpack an image.
#   - The container is prepared the way moby's hack/dind prepares it for a
#     nested daemon: securityfs, cgroup v2 nesting, a shared root mount.
#     https://github.com/moby/moby/blob/master/hack/dind
#   - Debian's nft iptables, with the legacy backend as the fallback that the
#     docker:dind entrypoint also uses.
#   - The bridge MTU is the job interface's (1360 on the hosted runners, where
#     Docker's default is 1500), for the default bridge and for every network
#     compose creates later.
#   - Docker Hub pulls go through the mirror.gcr.io pull-through cache, so
#     the shared runners' addresses meet Docker Hub's anonymous limit less often.
#
# The daemon listens on unix:///var/run/docker.sock; the job sets DOCKER_HOST
# to that socket. It logs to tmp/ci/dockerd.log. The job container is
# replaced before after_script, so the daemon and its containers are gone
# there; bin/ci services and bin/ci lane collect service logs themselves.
set -euo pipefail

# shellcheck source=tools/ci/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SOCKET=unix:///var/run/docker.sock
REGISTRY_MIRROR=https://mirror.gcr.io

case "${1:-}" in
  up)
    shift
    [ "$#" -eq 0 ] || ci_usage_error "usage: bin/ci docker up"
    ;;
  *) ci_usage_error "usage: bin/ci docker up" ;;
esac

if docker info > /dev/null 2>&1; then
  printf 'bin/ci docker up: a Docker daemon answers at %s; nothing to start\n' "${DOCKER_HOST:-the default socket}"
  exit 0
fi

ci_require_gitlab_job "bin/ci docker up (starting a daemon)"
[ "$(id -u)" -eq 0 ] || ci_die "starting dockerd needs root"
command -v dockerd > /dev/null 2>&1 || ci_die "dockerd is not installed (bin/ci toolchain installs it)"
if [ -n "${DOCKER_HOST:-}" ] && [ "$DOCKER_HOST" != "$SOCKET" ]; then
  ci_die "DOCKER_HOST is ${DOCKER_HOST}, which does not answer; the daemon started here listens on ${SOCKET}"
fi
export DOCKER_HOST="$SOCKET"
unset DOCKER_TLS_VERIFY DOCKER_CERT_PATH

mkdir -p "$CI_OUT_DIR"
DOCKERD_LOG="${CI_OUT_DIR}/dockerd.log"

# cgroup v2 nesting (hack/dind): move this container's processes out of its
# root cgroup so that controllers can be delegated to the cgroups dockerd
# creates. Bounded, where the original loops until it succeeds. Skipped when
# the job is not at the root of its own cgroup namespace, because the same
# writes would then act on cgroups that are not this container's.
cgroup_nesting() {
  local attempt
  [ -f /sys/fs/cgroup/cgroup.controllers ] || return 0
  [ "$(cat /proc/self/cgroup)" = "0::/" ] || return 0
  [ -n "$(cat /sys/fs/cgroup/cgroup.controllers)" ] || return 0
  mkdir -p /sys/fs/cgroup/init
  for attempt in $(seq 1 20); do
    xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs 2> /dev/null || :
    if sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers \
      > /sys/fs/cgroup/cgroup.subtree_control 2> /dev/null; then
      printf 'bin/ci docker up: cgroup nesting after %s attempt(s)\n' "$attempt"
      return 0
    fi
  done
  printf 'bin/ci docker up: cgroup nesting failed after 20 attempts; starting dockerd anyway\n' >&2
}

prepare_container() {
  # AppArmor detection in dockerd and containerd (hack/dind).
  export container=docker
  if [ -d /sys/kernel/security ] && ! mountpoint -q /sys/kernel/security; then
    mount -t securityfs none /sys/kernel/security ||
      printf 'bin/ci docker up: could not mount /sys/kernel/security\n' >&2
  fi
  cgroup_nesting
  mount --make-rshared /
}

select_iptables() {
  iptables -nL > /dev/null 2>&1 && return 0
  printf 'bin/ci docker up: iptables (nft) failed; switching to iptables-legacy\n' >&2
  update-alternatives --set iptables /usr/sbin/iptables-legacy
  update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
  iptables -nL > /dev/null 2>&1 || ci_die "iptables does not work with either backend"
}

start_dockerd() {
  local root mtu pid i
  root="${CI_BUILDS_DIR:-/builds}/.ci-docker"
  mtu="$(cat /sys/class/net/eth0/mtu 2> /dev/null || true)"
  mkdir -p "$root"
  local -a args=(--host "$SOCKET" --data-root "$root" --registry-mirror "$REGISTRY_MIRROR")
  if [ -n "$mtu" ]; then
    # --mtu covers the default bridge only; --default-network-opt covers the
    # networks created later, compose's included.
    # https://docs.docker.com/reference/cli/dockerd/
    args+=(--mtu "$mtu" --default-network-opt "bridge=com.docker.network.driver.mtu=${mtu}")
  fi
  printf 'bin/ci docker up: dockerd %s\n' "${args[*]}" | tee -a "$DOCKERD_LOG"
  # Detached from this script and from the job's output pipe: the daemon
  # outlives this command and must not keep the job log open.
  setsid nohup dockerd "${args[@]}" >> "$DOCKERD_LOG" 2>&1 < /dev/null &
  pid=$!
  for i in $(seq 1 60); do
    if docker info > /dev/null 2>&1; then
      printf 'bin/ci docker up: daemon ready after %ss (storage driver %s, data root %s)\n' \
        "$i" "$(docker info --format '{{.Driver}}')" "$(docker info --format '{{.DockerRootDir}}')"
      return 0
    fi
    kill -0 "$pid" 2> /dev/null || break
    sleep 1
  done
  tail -60 "$DOCKERD_LOG" >&2 || true
  ci_die "dockerd did not answer (log in tmp/ci/dockerd.log)"
}

ci_section_start docker_up "Start a Docker daemon in the job"
prepare_container
select_iptables
start_dockerd
ci_section_end docker_up
