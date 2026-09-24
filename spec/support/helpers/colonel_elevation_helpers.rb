# spec/support/helpers/colonel_elevation_helpers.rb
#
# frozen_string_literal: true

# Drive the colonel step-up (sudo) window from a unit spec (#4327).
#
# spec/config.test.yaml ships `site.admin.elevation.enabled: false` so the
# colonel suites — which hit many destructive endpoints from one process as one
# actor — are not gated. Every spec that wants the gate ON therefore turns it on
# in-process, which is what {#stub_colonel_elevation} does.
#
# It stubs `OT.conf` with a DEEP COPY rather than mutating the live hash: the
# global after(:each) restores `@conf` only when `OT.conf != @__original_ot_conf`,
# and an in-place mutation compares equal to itself, so the change would leak
# into every later example in the process.
module ColonelElevationHelpers
  # Replace OT.conf for this example with one whose site.admin.elevation block
  # says what the caller asked for. Everything else in the config is preserved.
  #
  # @param enabled [Boolean]
  # @param window [Integer] elevation lifetime in seconds
  # @param reauth_grace [Integer] 0 = the password-less grace is OFF (shipped default)
  # @return [Hash] the stubbed config
  def stub_colonel_elevation(enabled: true, window: 600, reauth_grace: 0)
    conf = deep_dup_conf(OT.conf)
    conf['site'] ||= {}
    conf['site']['admin'] ||= {}
    conf['site']['admin']['elevation'] = {
      'enabled' => enabled,
      'window' => window,
      'reauth_grace' => reauth_grace,
    }
    allow(OT).to receive(:conf).and_return(conf)
    conf
  end

  # A session hash carrying a live, identity-bound elevation record — the exact
  # shape ColonelAPI::Logic::Colonel::Elevation#grant_elevation! writes.
  #
  # @param extid [String] the acting colonel's PUBLIC id; a record naming any
  #   other identity must be ignored, which is what the B-2 cases assert.
  # @param expires_in [Integer] seconds from now; pass a negative value for an
  #   expired window.
  def elevated_session(extid, expires_in: 600)
    { 'elevated_until' => { 'extid' => extid.to_s, 'exp' => Familia.now.to_i + expires_in } }
  end

  private

  def deep_dup_conf(conf)
    YAML.load(YAML.dump(conf))
  end
end

RSpec.configure do |config|
  config.include ColonelElevationHelpers
end
