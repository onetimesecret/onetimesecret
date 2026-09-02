# spec/unit/onetime/config/admin_defaults_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'erb'
require 'yaml'
require 'onetime/operations/ratelimit/registry'

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
    COLONEL_MUTATION_RATE_LIMIT_ENABLED COLONEL_MUTATION_MAX_ATTEMPTS
    COLONEL_MUTATION_RATE_WINDOW COLONEL_MUTATION_LOCKOUT
    COLONEL_DESTRUCTIVE_RATE_LIMIT_ENABLED COLONEL_DESTRUCTIVE_MAX_ATTEMPTS
    COLONEL_DESTRUCTIVE_RATE_WINDOW COLONEL_DESTRUCTIVE_LOCKOUT
    COLONEL_HANDLE_RESOLVE_RATE_LIMIT_ENABLED COLONEL_HANDLE_RESOLVE_MAX_ATTEMPTS
    COLONEL_HANDLE_RESOLVE_RATE_WINDOW COLONEL_HANDLE_RESOLVE_LOCKOUT
    ADMIN_SESSION_LIFETIME_ENABLED ADMIN_SESSION_IDLE_TIMEOUT ADMIN_SESSION_ABSOLUTE_TIMEOUT
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

  describe 'colonel API rate limits (#4327 elevation bucket; #4329 the other three)' do
    it 'ships ENABLED at the parent flag' do
      expect(admin.dig('rate_limit', 'enabled')).to be true
    end

    # Sizing, not just the flag: the numbers ARE the control. A default quietly
    # raised to 10 000 would leave every example green while restoring the
    # unbounded posture #4329 exists to remove.
    {
      'elevation' => { max: 5, window: 900, lockout: 900 },
      'mutation' => { max: 120, window: 300, lockout: 300 },
      'destructive' => { max: 10, window: 300, lockout: 900 },
      'handle_resolve' => { max: 60, window: 300, lockout: 300 },
    }.each do |name, sizing|
      it "ships the #{name} bucket enabled with its documented sizing" do
        bucket = admin.dig('rate_limit', name)

        expect(bucket).to be_a(Hash), "site.admin.rate_limit.#{name} is missing from the shipped defaults"
        expect(bucket['enabled']).to be true
        expect(bucket['max_attempts'].to_i).to eq(sizing[:max])
        expect(bucket['window'].to_i).to eq(sizing[:window])
        expect(bucket['lockout'].to_i).to eq(sizing[:lockout])
      end
    end

    # The registry rows are what make `bin/ots ratelimit`, GET
    # /ratelimit/inspect and POST /ratelimit/reset able to see these keys, and
    # POST /ratelimit/reset is the documented recovery for an operator who locks
    # themselves out of destructive actions. A shipped bucket with no row is a
    # limiter no operator can clear.
    it 'has a registry row for every shipped bucket' do
      kinds = Onetime::Operations::RateLimit::Registry.kinds

      expect(kinds).to include(
        'colonel_elevation', 'colonel_mutation', 'colonel_destructive', 'colonel_handle_resolve'
      )
    end
  end

  describe 'admin-surface session bounds (#4331)' do
    it 'ships ENABLED' do
      expect(admin.dig('session', 'enabled')).to be true
    end

    # The numbers are the control. A default quietly raised to 86 400 would
    # restore the 24h rolling posture #4331 exists to bound, with every example
    # still green.
    it 'ships a 1-hour idle bound' do
      expect(admin.dig('session', 'idle_timeout').to_i).to eq(3_600)
    end

    it 'ships a 12-hour absolute bound' do
      expect(admin.dig('session', 'absolute_timeout').to_i).to eq(43_200)
    end

    # Both bounds must be shorter than the session object's own rolling TTL, or
    # the admin surface would outlive the cookie and the feature would be inert.
    it 'ships both bounds shorter than site.session.expire_after' do
      expire_after = Onetime::Initializers::SESSION_DEFAULTS['expire_after']

      expect(admin.dig('session', 'idle_timeout').to_i).to be < expire_after
      expect(admin.dig('session', 'absolute_timeout').to_i).to be < expire_after
    end
  end

  describe 'the test config deliberately differs' do
    # Stated as an assertion so the divergence is visible rather than surprising:
    # if someone "fixes" the test config to match the shipped one, the colonel
    # suites start gating themselves and this spec explains why they must not.
    it 'disables all three in spec/config.test.yaml' do
      expect(OT.conf.dig('site', 'admin', 'elevation', 'enabled')).to be false
      expect(OT.conf.dig('site', 'admin', 'rate_limit', 'enabled')).to be false
      expect(OT.conf.dig('site', 'admin', 'session', 'enabled')).to be false
    end
  end
end
