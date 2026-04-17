# try/unit/sentry_doctor_release_try.rb
#
# frozen_string_literal: true

# These tryouts validate the Sentry release-resolution contract shared
# between two call sites:
#
#   1. runtime  -- Onetime::Initializers::SetupDiagnostics#resolve_sentry_release
#   2. CLI      -- Onetime::CLI::Diagnostics::SentryDoctorCommand#deliver_via_sdk
#
# Fix 2 brings the CLI site in line with the runtime site so that
# doctor-originated events group under the same release as live events.
#
# Strategy:
#   - Behavioral: replicate the documented resolution rules in a helper
#     and assert the three input branches (env set / env unset / env blank).
#   - Regression: string-match the CLI source to ensure it keeps using the
#     same pattern rather than silently regressing back to a literal
#     release string like 'cli'.
#
# The `deliver_via_sdk` method itself calls Sentry.init + network I/O and
# cannot be exercised in a unit test.

require_relative '../support/test_helpers'

OT.boot! :test, false

require 'onetime/version'

# Helper mirroring Onetime::Initializers::SetupDiagnostics#resolve_sentry_release.
# If the CLI site and runtime site agree, both will produce the value this
# helper produces for the same ENV state.
def resolve_release
  env_release = ENV.fetch('SENTRY_RELEASE', '').strip
  return env_release unless env_release.empty?

  OT::VERSION.get_build_info
end

# Preserve the caller's ENV so teardown can restore it.
@original_sentry_release = ENV['SENTRY_RELEASE']

# Compute the build-info fallback once for equality checks below.
@build_info_fallback = OT::VERSION.get_build_info

# Path to the CLI source file we're guarding against regression.
@doctor_source_path = File.expand_path(
  '../../lib/onetime/cli/diagnostics/sentry/doctor_command.rb',
  __dir__,
)
@doctor_source = File.read(@doctor_source_path)

# -----------------------------------------------------------------------------
# Behavioral equivalence tests
# -----------------------------------------------------------------------------

## With SENTRY_RELEASE set, resolver returns the env value
ENV['SENTRY_RELEASE'] = 'v1.2.3'
resolve_release
#=> 'v1.2.3'

## With SENTRY_RELEASE unset, resolver falls back to OT::VERSION.get_build_info
ENV.delete('SENTRY_RELEASE')
resolve_release
#=> @build_info_fallback

## With SENTRY_RELEASE set to empty string, resolver falls back (empty stripped)
ENV['SENTRY_RELEASE'] = ''
resolve_release
#=> @build_info_fallback

## With SENTRY_RELEASE set to whitespace only, resolver falls back (strip check)
ENV['SENTRY_RELEASE'] = '   '
resolve_release
#=> @build_info_fallback

## With SENTRY_RELEASE padded with surrounding whitespace, value is stripped
ENV['SENTRY_RELEASE'] = "  v9.9.9\n"
resolve_release
#=> 'v9.9.9'

## Explicit override survives even when value looks like a commit hash
ENV['SENTRY_RELEASE'] = 'deadbee'
resolve_release
#=> 'deadbee'

# -----------------------------------------------------------------------------
# Source-level regression guards (proves CLI site keeps using the pattern)
# -----------------------------------------------------------------------------

## doctor_command.rb requires 'time' (Fix 3 -- ensures Time#iso8601 is available)
@doctor_source.include?("require 'time'")
#=> true

## doctor_command.rb references SENTRY_RELEASE env var in deliver_via_sdk
@doctor_source.include?("ENV.fetch('SENTRY_RELEASE'")
#=> true

## doctor_command.rb still uses OT::VERSION.get_build_info as fallback
@doctor_source.include?('OT::VERSION.get_build_info')
#=> true

## doctor_command.rb strips the env value (prevents whitespace slip-through)
@doctor_source.match?(/SENTRY_RELEASE['"]\s*,\s*['"]{2}\s*\)\s*\.strip/)
#=> true

## The release block lives inside the Sentry.init configuration
# (We want to be sure the logic is applied to c.release, not dead code.)
@doctor_source.match?(/c\.release\s*=.*SENTRY_RELEASE/m)
#=> true

## Fallback string 'cli' still exists as last-resort when OT::VERSION is undefined
# This preserves the CLI's safety net (cli tools can load without Onetime boot).
@doctor_source.include?("'cli'")
#=> true

## setup_diagnostics.rb still defines resolve_sentry_release (the runtime site
## the CLI mirrors -- if this ever moves, CLI should move with it)
setup_source = File.read(File.expand_path(
  '../../lib/onetime/initializers/setup_diagnostics.rb',
  __dir__,
))
setup_source.include?('def resolve_sentry_release')
#=> true

# -----------------------------------------------------------------------------
# Teardown -- restore original ENV
# -----------------------------------------------------------------------------
if @original_sentry_release.nil?
  ENV.delete('SENTRY_RELEASE')
else
  ENV['SENTRY_RELEASE'] = @original_sentry_release
end
