# try/docker/version_validation_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::VERSION module which reads version from package.json.
# This is the runtime version system used by the application, and the source
# of truth for the version displayed in Docker images.
#
# The version lifecycle:
#   1. package.json ships with "0.0.0-rc0" (development archetype)
#   2. CI runs update-version.sh to set the real version before docker build
#   3. Dockerfile build stage validates package.json is not still 0.0.0-rc0
#   4. version.rb reads package.json at runtime to report the version
#
# These tests verify step 4: that version.rb correctly parses all version
# formats that steps 1-3 can produce.

require 'oj'
require 'familia/json_serializer'

ENV['RACK_ENV'] = 'test'
ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '..', '..')).freeze

require 'onetime'
require 'onetime/version'

# Helper to test version parsing for arbitrary version strings without
# touching the real package.json. Resets the cached @version, injects a
# temporary package.json, runs load_config, then restores the original.
def with_version(version_string)
  # Reset cached version
  Onetime::VERSION.instance_variable_set(:@version, nil)

  package_json_path = File.join(Onetime::HOME, 'package.json')
  original_content = File.read(package_json_path)
  temp_content = Familia::JsonSerializer.parse(original_content)
  temp_content['version'] = version_string

  # Write temporary package.json
  File.write(package_json_path, JSON.generate(temp_content))

  Onetime::VERSION.load_config
  result = yield
  result
ensure
  # Restore original package.json and reset cache
  File.write(package_json_path, original_content)
  Onetime::VERSION.instance_variable_set(:@version, nil)
end

# Reset any previously cached version so tests start clean
Onetime::VERSION.instance_variable_set(:@version, nil)


## Parses the development archetype version (0.0.0-rc0) from package.json
with_version('0.0.0-rc0') { Onetime::VERSION.to_s }
#=> '0.0.0-rc0'

## Returns correct array for development archetype
with_version('0.0.0-rc0') { Onetime::VERSION.to_a }
#=> ['0', '0', '0']

## Parses a standard release version
with_version('0.24.0') { Onetime::VERSION.to_s }
#=> '0.24.0'

## Returns correct array for standard release
with_version('0.24.0') { Onetime::VERSION.to_a }
#=> ['0', '24', '0']

## Parses a release candidate version
with_version('0.24.2-rc1') { Onetime::VERSION.to_s }
#=> '0.24.2-rc1'

## Returns correct array for release candidate (pre-release not in array)
with_version('0.24.2-rc1') { Onetime::VERSION.to_a }
#=> ['0', '24', '2']

## Parses a major release version
with_version('1.0.0') { Onetime::VERSION.to_s }
#=> '1.0.0'

## Returns correct array for major release
with_version('1.0.0') { Onetime::VERSION.to_a }
#=> ['1', '0', '0']

## Parses a nightly build version
with_version('0.0.0-nightly.20260314') { Onetime::VERSION.to_s }
#=> '0.0.0-nightly.20260314'

## Parses a branch build version
with_version('0.0.0-develop.abc1234') { Onetime::VERSION.to_s }
#=> '0.0.0-develop.abc1234'

## Version without pre-release has nil PRE field
with_version('1.2.3') do
  Onetime::VERSION.load_config
  Onetime::VERSION.instance_variable_get(:@version)[:PRE]
end
#=> nil

## Version with pre-release has correct PRE field
with_version('1.2.3-beta.1') do
  Onetime::VERSION.instance_variable_get(:@version)[:PRE]
end
#=> 'beta.1'

## details includes build info when a commit hash is available
with_version('0.24.0') do
  details = Onetime::VERSION.details
  # details is either "0.24.0" or "0.24.0 (commit_hash)"
  details.start_with?('0.24.0')
end
#=> true

## details format includes parenthesized build info
with_version('0.24.0') do
  details = Onetime::VERSION.details
  # In local dev with git, should have build info in parens
  # In Docker without git, would just be the version string
  details.match?(/\A0\.24\.0(\s+\(.+\))?\z/)
end
#=> true

## user_agent returns properly formatted string
with_version('0.24.0') do
  ua = Onetime::VERSION.user_agent
  ua.match?(/\AOnetimeWorker\/0\.24\.0 \(Ruby\//)
end
#=> true

## get_build_info returns a non-empty string
Onetime::VERSION.instance_variable_set(:@version, nil)
build_info = Onetime::VERSION.get_build_info
build_info.is_a?(String) && !build_info.empty?
#=> true

## get_build_info with dev commit_hash falls back to git or dev
# The "dev" and "pristine" values in .commit_hash.txt are treated as fallback
# and skipped in favor of git rev-parse or the final "dev" fallback.
build_info = Onetime::VERSION.get_build_info
%w[dev pristine].include?(build_info) || build_info.match?(/\A[0-9a-f]+\z/)
#=> true

## High major version parses correctly
with_version('42.0.1') { Onetime::VERSION.to_a }
#=> ['42', '0', '1']

## Multi-digit minor and patch parse correctly
with_version('2.15.103') { Onetime::VERSION.to_a }
#=> ['2', '15', '103']

## Pre-release with multiple segments parses correctly
with_version('1.0.0-alpha.1.2') { Onetime::VERSION.to_s }
#=> '1.0.0-alpha.1.2'


# --- CI version pattern coverage ---
# These tests verify every version pattern that CI can produce (see
# .github/workflows/build-and-publish-oci-images.yml lines 108-119):
#   - Tag push:       real semver like 0.24.2
#   - Manual dispatch: user-provided version (e.g. 0.24.2-rc1)
#   - Scheduled:      0.0.0-nightly.YYYYMMDD
#   - Branch push:    0.0.0-BRANCH_SLUG.SHORT_SHA

## to_a for nightly build returns string array ['0','0','0']
with_version('0.0.0-nightly.20260314') { Onetime::VERSION.to_a }
#=> ['0', '0', '0']

## to_a for branch build returns string array ['0','0','0']
with_version('0.0.0-develop.abc1234') { Onetime::VERSION.to_a }
#=> ['0', '0', '0']

## to_a elements are always String type, never Integer
with_version('0.24.2') do
  Onetime::VERSION.to_a.all? { |v| v.is_a?(String) }
end
#=> true

## to_a elements for archetype are String type
with_version('0.0.0-rc0') do
  Onetime::VERSION.to_a.all? { |v| v.is_a?(String) }
end
#=> true

## to_s round-trips for tag release version 0.24.2
with_version('0.24.2') { Onetime::VERSION.to_s }
#=> '0.24.2'

## to_a for tag release version 0.24.2
with_version('0.24.2') { Onetime::VERSION.to_a }
#=> ['0', '24', '2']

## PRE field for nightly contains full suffix nightly.20260314
with_version('0.0.0-nightly.20260314') do
  Onetime::VERSION.instance_variable_get(:@version)[:PRE]
end
#=> 'nightly.20260314'

## PRE field for branch build contains full suffix develop.abc1234
with_version('0.0.0-develop.abc1234') do
  Onetime::VERSION.instance_variable_get(:@version)[:PRE]
end
#=> 'develop.abc1234'

## PRE field for archetype is rc0
with_version('0.0.0-rc0') do
  Onetime::VERSION.instance_variable_get(:@version)[:PRE]
end
#=> 'rc0'

## details for nightly build starts with the full version string
with_version('0.0.0-nightly.20260314') do
  Onetime::VERSION.details.start_with?('0.0.0-nightly.20260314')
end
#=> true

## details for branch build starts with the full version string
with_version('0.0.0-develop.abc1234') do
  Onetime::VERSION.details.start_with?('0.0.0-develop.abc1234')
end
#=> true

## details for archetype starts with 0.0.0-rc0
with_version('0.0.0-rc0') do
  Onetime::VERSION.details.start_with?('0.0.0-rc0')
end
#=> true

## user_agent includes pre-release suffix for nightly
with_version('0.0.0-nightly.20260314') do
  ua = Onetime::VERSION.user_agent
  ua.match?(/\AOnetimeWorker\/0\.0\.0-nightly\.20260314 \(Ruby\//)
end
#=> true

## 1.0.0-rc0 is a valid non-archetype pre-release (only 0.0.0-rc0 is archetype)
with_version('1.0.0-rc0') { Onetime::VERSION.to_s }
#=> '1.0.0-rc0'

## 10.0.0 parses correctly (does not false-match 0.0.0 prefix)
with_version('10.0.0') { Onetime::VERSION.to_s }
#=> '10.0.0'

## 10.0.0 to_a returns correct segments
with_version('10.0.0') { Onetime::VERSION.to_a }
#=> ['10', '0', '0']

# --- Branch names with hyphens ---
# When branch slug contains hyphens (e.g. feature/my-thing -> feature-my-thing),
# CI produces "0.0.0-feature-my-thing.abc1234". Using split('-', 2) ensures the
# full pre-release string is preserved.

## Branch slug with hyphens preserves full pre-release suffix
with_version('0.0.0-feature-my-thing.abc1234') do
  Onetime::VERSION.instance_variable_get(:@version)[:PRE]
end
#=> 'feature-my-thing.abc1234'

## Branch slug with hyphens round-trips through to_s
with_version('0.0.0-feature-my-thing.abc1234') { Onetime::VERSION.to_s }
#=> '0.0.0-feature-my-thing.abc1234'

# Teardown - Restore original version cache state
Onetime::VERSION.instance_variable_set(:@version, nil)
