#!/usr/bin/env bash
# Pins this checkout to another Ruby version, for a workflow that runs the
# suite under a Ruby other than the repository's (ruby-4-preview.yml).
#
# The Gemfile reads its Ruby requirement from .ruby-version (`ruby file:`), so
# Bundler refuses to load the bundle under any other Ruby
# (Bundler::RubyVersionMismatch). Gemfile.lock records the same version under
# RUBY VERSION, and a frozen (deployment) install refuses to rewrite it. This
# rewrites both and nothing else: the locked gem set stays as committed, so a
# gem that cannot install under the new Ruby fails the install rather than
# being re-resolved.
#
# Usage, from the repository root:
#   .github/scripts/pin-ruby-version.sh 4.0.2
#
# Exits non-zero and writes nothing when the version is not x.y.z or the
# lockfile has no RUBY VERSION entry. The result is for a CI checkout only;
# never commit it.
set -euo pipefail

fail() {
  printf '::error::%s\n' "$1" >&2
  exit 1
}

[[ $# -eq 1 ]] || fail 'Usage: pin-ruby-version.sh VERSION'
version="$1"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Not an x.y.z Ruby version: ${version}"
[[ -f .ruby-version && -f Gemfile.lock ]] \
  || fail 'Run from the repository root: .ruby-version and Gemfile.lock are required.'

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# The entry is the line after the RUBY VERSION header: "  ruby 3.4.10".
awk -v v="$version" '
  pending && /^  ruby / { print "  ruby " v; pending = 0; pinned = 1; next }
  { pending = ($0 == "RUBY VERSION"); print }
  END { exit !pinned }
' Gemfile.lock > "$tmp" || fail 'Gemfile.lock has no RUBY VERSION entry to pin.'

was="$(cat .ruby-version)"
cat "$tmp" > Gemfile.lock
printf '%s\n' "$version" > .ruby-version
printf '::notice::Pinned the checkout to Ruby %s (was %s): .ruby-version and Gemfile.lock\n' \
  "$version" "$was"
