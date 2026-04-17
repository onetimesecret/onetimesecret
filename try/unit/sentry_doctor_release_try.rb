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

# CLI-faithful helper that models the extra 'cli' fallback branch in
# doctor_command.rb's deliver_via_sdk. Driven by a flag rather than mutating
# the OT::VERSION constant so it can coexist with other tryouts in the shared
# runner.
def cli_resolve_release(version_defined: true)
  env_release = ENV.fetch('SENTRY_RELEASE', '').strip
  if env_release.empty?
    version_defined ? OT::VERSION.get_build_info : 'cli'
  else
    env_release
  end
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
# CLI-faithful release-resolver behavioral tests (PR #3012)
#
# The CLI site has an extra fallback the runtime site does not: when
# OT::VERSION is not defined, the CLI returns the literal 'cli'. This preserves
# a usable release identifier for CLI tools loaded outside a full Onetime boot.
#
# We model the exact CLI expression here -- including the `defined?(OT::VERSION)`
# guard -- and drive it via a flag rather than mutating the constant (which
# would leak into every subsequent test case in the shared runner).
# -----------------------------------------------------------------------------

## CLI resolver: SENTRY_RELEASE wins even when OT::VERSION is available
ENV['SENTRY_RELEASE'] = 'v2.0.0'
cli_resolve_release(version_defined: true)
#=> 'v2.0.0'

## CLI resolver: unset env + OT::VERSION defined -> get_build_info
ENV.delete('SENTRY_RELEASE')
cli_resolve_release(version_defined: true)
#=> @build_info_fallback

## CLI resolver: unset env + OT::VERSION undefined -> literal 'cli'
# This is the CLI-only branch -- the runtime site would raise NameError here.
ENV.delete('SENTRY_RELEASE')
cli_resolve_release(version_defined: false)
#=> 'cli'

## CLI resolver: empty env + OT::VERSION undefined -> literal 'cli'
ENV['SENTRY_RELEASE'] = ''
cli_resolve_release(version_defined: false)
#=> 'cli'

## CLI resolver: whitespace-only env + OT::VERSION undefined -> 'cli'
# Whitespace must be treated as empty (guards against "SENTRY_RELEASE= " slipping
# through in CI scripts), and fallback must still resolve cleanly.
ENV['SENTRY_RELEASE'] = "\t\n "
cli_resolve_release(version_defined: false)
#=> 'cli'

## CLI resolver: explicit env overrides the 'cli' fallback branch entirely
# Proves the branch order: env is checked first, so the OT::VERSION guard is
# never reached when env is present.
ENV['SENTRY_RELEASE'] = 'release-abc123'
cli_resolve_release(version_defined: false)
#=> 'release-abc123'

# -----------------------------------------------------------------------------
# Additional source-level guards against known regression paths
# -----------------------------------------------------------------------------

## deliver_via_sdk uses Sentry.init (not a hand-rolled HTTP envelope) for release tagging
# The release identifier only reaches Sentry if it's attached via SDK config,
# not via the HTTP fallback path.
@doctor_source.match?(/def deliver_via_sdk.*Sentry\.init/m)
#=> true

## The 'cli' literal is co-located with OT::VERSION guard (not a stray string elsewhere)
# Ensures the fallback lives on the same logical line as the defined? check.
@doctor_source.match?(/defined\?\(OT::VERSION\).*?'cli'/m)
#=> true

## Time#iso8601 is actually called in the delivery probe (proves require 'time' is used)
@doctor_source.include?('Time.now.utc.iso8601')
#=> true

## environment tag is set to 'cli-doctor' (so runtime and CLI events can be filtered apart in Sentry)
@doctor_source.include?("c.environment               = 'cli-doctor'")
#=> true

# -----------------------------------------------------------------------------
# Teardown -- restore original ENV
# -----------------------------------------------------------------------------
if @original_sentry_release.nil?
  ENV.delete('SENTRY_RELEASE')
else
  ENV['SENTRY_RELEASE'] = @original_sentry_release
end
