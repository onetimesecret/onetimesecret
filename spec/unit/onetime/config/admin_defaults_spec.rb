# spec/unit/onetime/config/admin_defaults_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'erb'
require 'yaml'

# The SHIPPED posture of the colonel hardening switches, read from
# etc/defaults/config.defaults.yaml itself.
#
# Why this file exists: spec/config.test.yaml disables step-up and the colonel
# rate limits so the suites (many destructive endpoints, one process, one actor)
# are not gated. Without a counter-spec, the DISABLED posture would be the only
# one under test, and a regression that flipped a shipped default to `false`
# would pass every example except the two that opt in — i.e. it would ship.
#
# It renders the defaults file the way boot does (ERB, then YAML) with the
# relevant env vars cleared, so what is asserted is what an operator who set
# nothing actually gets.
RSpec.describe 'etc/defaults/config.defaults.yaml — admin defaults' do
  DEFAULTS_PATH = File.join(Onetime::HOME, 'etc', 'defaults', 'config.defaults.yaml')

  # Env vars that could otherwise mask a changed default in a developer shell.
  ADMIN_ENV_KEYS = %w[
    COLONEL_ELEVATION_ENABLED COLONEL_ELEVATION_WINDOW COLONEL_ELEVATION_REAUTH_GRACE
    COLONEL_RATE_LIMIT_ENABLED COLONEL_ELEVATION_RATE_LIMIT_ENABLED
    COLONEL_ELEVATION_MAX_ATTEMPTS COLONEL_ELEVATION_RATE_WINDOW COLONEL_ELEVATION_LOCKOUT
  ].freeze

  let(:admin) do
    saved = ADMIN_ENV_KEYS.to_h { |key| [key, ENV.fetch(key, nil)] }
    ADMIN_ENV_KEYS.each { |key| ENV.delete(key) }
    begin
      rendered = ERB.new(File.read(DEFAULTS_PATH), trim_mode: '-').result(binding)
      YAML.unsafe_load(rendered).dig('site', 'admin')
    ensure
      saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
  end

  it 'parses (a broken ERB/YAML default would break boot, not just this spec)' do
    expect(admin).to be_a(Hash)
  end

  describe 'step-up (sudo) re-authentication (#4327)' do
    it 'ships ENABLED' do
      expect(admin.dig('elevation', 'enabled')).to be true
    end

    it 'ships a 10-minute window' do
      expect(admin.dig('elevation', 'window').to_i).to eq(600)
    end

    # The B-3 lock. A non-zero default would make step-up a no-op for the first
    # N seconds after every colonel sign-in, which is the exact condition #4327
    # exists to remove.
    it 'ships the password-less grace OFF' do
      expect(admin.dig('elevation', 'reauth_grace').to_i).to eq(0)
    end
  end

  describe 'colonel API rate limits (#4327 elevation bucket; #4329 adds the rest)' do
    it 'ships ENABLED at the parent flag' do
      expect(admin.dig('rate_limit', 'enabled')).to be true
    end

    it 'ships the elevation bucket enabled with its documented sizing' do
      bucket = admin.dig('rate_limit', 'elevation')

      expect(bucket['enabled']).to be true
      expect(bucket['max_attempts'].to_i).to eq(5)
      expect(bucket['window'].to_i).to eq(900)
      expect(bucket['lockout'].to_i).to eq(900)
    end
  end

  describe 'the test config deliberately differs' do
    # Stated as an assertion so the divergence is visible rather than surprising:
    # if someone "fixes" the test config to match the shipped one, the colonel
    # suites start gating themselves and this spec explains why they must not.
    it 'disables both in spec/config.test.yaml' do
      expect(OT.conf.dig('site', 'admin', 'elevation', 'enabled')).to be false
      expect(OT.conf.dig('site', 'admin', 'rate_limit', 'enabled')).to be false
    end
  end
end
