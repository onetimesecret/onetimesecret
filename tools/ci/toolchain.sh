#!/usr/bin/env bash
#
# tools/ci/toolchain.sh — bin/ci toolchain: install what a lane job needs
# beyond its Ruby image, at the start of the job.
#
# Interim. The toolchain image of the GitLab CI migration plan
# (docs/planning/2026-1110-gitlab-ci-migration-plan.md, §4.3) carries all of
# this, and a job on that image does not call this command. Spike S1 measured
# the cost on a hosted runner: about 20s for apt and the Docker engine, about
# 6s for Node and pnpm.
#
#   apt     iptables, iproute2, kmod, mount, procps, util-linux, xz-utils:
#           for dockerd and bin/ci docker up. python3: the locale compiler
#           (`pnpm run locales:sync`; locales/scripts/pyproject.toml asks for
#           3.11 or newer). libsodium23: rbnacl loads it at runtime (Gemfile).
#   docker  Docker Engine and the compose plugin from Docker's apt repository,
#           as https://docs.docker.com/engine/install/debian/ describes.
#   node    the latest release of the major in .node-version, checked against
#           the release's SHASUMS256.txt. actions/setup-node resolves the same
#           major the same way on GitHub.
#   pnpm    the version in package.json's packageManager field.
#
# GitLab CI only (ci_require_gitlab_job), as root.
set -euo pipefail

# shellcheck source=tools/ci/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ "$#" -eq 0 ] || ci_usage_error "usage: bin/ci toolchain"
ci_require_gitlab_job "bin/ci toolchain"
[ "$(id -u)" -eq 0 ] || ci_die "bin/ci toolchain installs system packages and needs root"
cd "$CI_REPO_ROOT"

export DEBIAN_FRONTEND=noninteractive

install_apt() {
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends \
    ca-certificates curl iproute2 iptables kmod mount procps util-linux \
    xz-utils python3 libsodium23 > /dev/null
}

install_docker() {
  local codename arch
  # shellcheck source=/dev/null
  codename="$(. /etc/os-release && printf '%s' "$VERSION_CODENAME")"
  arch="$(dpkg --print-architecture)"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  cat > /etc/apt/sources.list.d/docker.sources << EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${codename}
Components: stable
Architectures: ${arch}
Signed-By: /etc/apt/keyrings/docker.asc
EOF
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin > /dev/null
}

install_node() {
  local major base arch file work
  major="$(tr -d '[:space:]' < .node-version)"
  major="${major%%.*}"
  case "$(uname -m)" in
    x86_64) arch=x64 ;;
    aarch64) arch=arm64 ;;
    *) ci_die "no Node build for $(uname -m)" ;;
  esac
  base="https://nodejs.org/dist/latest-v${major}.x"
  work="$(mktemp -d)"
  curl -fsSL "${base}/SHASUMS256.txt" -o "${work}/SHASUMS256.txt"
  file="$(awk -v want="linux-${arch}.tar.xz" '$2 ~ want "$" { print $2 }' "${work}/SHASUMS256.txt")"
  [ -n "$file" ] || ci_die "no linux-${arch}.tar.xz in ${base}/SHASUMS256.txt"
  curl -fsSL "${base}/${file}" -o "${work}/${file}"
  (cd "$work" && grep " ${file}\$" SHASUMS256.txt | sha256sum -c -)
  tar -xJf "${work}/${file}" -C /usr/local --strip-components=1 \
    --exclude='*/CHANGELOG.md' --exclude='*/LICENSE' --exclude='*/README.md'
  rm -rf "$work"
}

install_pnpm() {
  local version
  version="$(node -p "require('./package.json').packageManager.split('@')[1].split('+')[0]")"
  npm install -g --silent "pnpm@${version}"
}

step() { # <id> <title> <function>
  local started=$SECONDS
  ci_section_start "$1" "$2"
  "$3"
  ci_section_end "$1"
  printf 'bin/ci toolchain: %s took %ss\n' "$1" "$((SECONDS - started))"
}

step toolchain_apt "apt packages" install_apt
step toolchain_docker "Docker Engine and compose" install_docker
step toolchain_node "Node from .node-version" install_node
step toolchain_pnpm "pnpm from package.json" install_pnpm

hash -r
printf 'bin/ci toolchain: ruby %s, node %s, pnpm %s, %s, docker %s, compose %s, bash %s\n' \
  "$(ruby -e 'print RUBY_VERSION')" "$(node -v)" "$(pnpm --version)" \
  "$(python3 --version)" "$(docker --version | awk '{ print $3 }' | tr -d ',')" \
  "$(docker compose version --short)" "$BASH_VERSION"
