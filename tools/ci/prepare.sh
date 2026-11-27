#!/usr/bin/env bash
#
# tools/ci/prepare.sh — bin/ci prepare [checkout|etc|bundle|pnpm]...: the job
# preparation a lane needs after its toolchain. What the setup-ruby-test-env
# and setup-node-env actions do on GitHub beyond installing Ruby and Node,
# and one step GitHub's checkout does not need:
#
#   checkout  group and other write access removed from the checkout's root
#             and the directories above it (see private_checkout below);
#   etc       etc/<name> from each etc/defaults/<name with .defaults>, where
#             etc/<name> is missing;
#   bundle    a frozen bundle install into vendor/bundle, in deployment mode,
#             set in the checkout's .bundle/config (what ruby/setup-ruby's
#             bundler-cache does);
#   pnpm      a frozen pnpm install.
#
# With no argument it runs all four, in that order. A job that needs less
# names its steps: the RuboCop job runs `bin/ci prepare bundle`, the frontend
# build `bin/ci prepare pnpm`.
#
# The official Ruby image points RubyGems and Bundler at /usr/local/bundle
# through GEM_HOME and BUNDLE_APP_CONFIG. tests/lanes/run clears both (they
# are not on its keep-list), so gems installed under them would be missing
# inside the lane. This command unsets them and relies on .bundle/config.
#
# GitLab CI only: it rewrites the checkout's .bundle/config.
set -euo pipefail

# shellcheck source=tools/ci/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

for name in "$@"; do
  case "$name" in
    checkout | etc | bundle | pnpm) ;;
    *) ci_usage_error "usage: bin/ci prepare [checkout|etc|bundle|pnpm]... (not a step: ${name})" ;;
  esac
done
[ "$#" -gt 0 ] || set -- checkout etc bundle pnpm
ci_require_gitlab_job "bin/ci prepare"
cd "$CI_REPO_ROOT"
unset GEM_HOME BUNDLE_APP_CONFIG

step() { # <id> <title> <function>
  local started=$SECONDS
  ci_section_start "$1" "$2"
  "$3"
  ci_section_end "$1"
  printf 'bin/ci prepare: %s took %ss\n' "$1" "$((SECONDS - started))"
}

# GitLab's Docker executor fetches the sources with umask 0000, so the
# checkout's root and the build directories above it are writable by every
# user. `bin/setup --doctor --bundle` refuses to write under such a directory
# (bundle_check_output_path in tools/setup/setup.sh), and the unit lane runs
# it (spec/unit/setup/doctor_bundle_spec.rb). A GitHub runner's checkout and
# a workstation's are writable by their owner only. A sticky directory is
# left alone: that check accepts one.
private_checkout() {
  local path="$CI_REPO_ROOT"
  while [ -n "$path" ] && [ "$path" != / ]; do
    if [ -O "$path" ] && [ ! -k "$path" ]; then
      chmod go-w "$path"
    fi
    printf '%s %s\n' "$(stat -c '%a %U' "$path")" "$path"
    path="$(dirname "$path")"
  done
}

seed_etc() {
  local file target
  for file in etc/defaults/*.defaults.*; do
    [ -f "$file" ] || continue
    target="etc/$(basename "$file" | sed 's/\.defaults//')"
    if [ ! -f "$target" ]; then
      cp "$file" "$target"
      printf 'Created %s from defaults\n' "$target"
    fi
  done
}

bundle_install() {
  local version cache=cold
  version="$(awk '/^BUNDLED WITH/ { getline; gsub(/ /, ""); print }' Gemfile.lock)"
  [ -n "$version" ] || ci_die "Gemfile.lock names no Bundler version (BUNDLED WITH)"
  gem install bundler -v "$version" --no-document
  bundle config set --local deployment true
  bundle config set --local path vendor/bundle
  [ -d vendor/bundle/ruby ] && cache=from-cache
  printf 'bin/ci prepare: vendor/bundle %s\n' "$cache"
  bundle install --jobs "$(nproc)"
}

pnpm_install() {
  pnpm install --frozen-lockfile
}

for name in "$@"; do
  case "$name" in
    checkout) step prepare_checkout "checkout writable by its owner only" private_checkout ;;
    etc) step prepare_etc "etc/ from etc/defaults" seed_etc ;;
    bundle) step prepare_bundle "bundle install (frozen, vendor/bundle)" bundle_install ;;
    pnpm) step prepare_pnpm "pnpm install (frozen)" pnpm_install ;;
  esac
done
