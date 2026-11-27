#!/usr/bin/env bash
#
# tools/ci/rubocop.sh — bin/ci rubocop: RuboCop over the whole tree, with the
# options of the ruby-lint job in .github/workflows/ci.yml: the repository's
# .rubocop.yml, offenses at warning level and above fail, progress on the
# console and the JSON report in tmp/rubocop_results.json.
#
# The official Ruby image points RubyGems and Bundler at /usr/local/bundle
# through GEM_HOME and BUNDLE_APP_CONFIG. `bin/ci prepare bundle` installs
# into vendor/bundle and records that in the checkout's .bundle/config, which
# Bundler reads only when BUNDLE_APP_CONFIG does not point elsewhere. This
# command unsets both, as bin/ci prepare and bin/ci lane do.
#
# It changes nothing on the machine, so it runs outside a GitLab job too.
set -uo pipefail

# shellcheck source=tools/ci/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ "$#" -eq 0 ] || ci_usage_error "usage: bin/ci rubocop"
cd "$CI_REPO_ROOT" || exit 1
unset GEM_HOME BUNDLE_APP_CONFIG
mkdir -p tmp

exec bundle exec rubocop --config .rubocop.yml \
  --format progress \
  --format json --out tmp/rubocop_results.json \
  --fail-level warning
