# spec/integration/all/initializers/setup_connection_pool_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'connection_pool'
require 'fileutils'
require 'yaml'
require 'erb'

# Integration coverage for the SetupConnectionPool initializer.
#
# The initializer is exercised transitively by boot_part1/2_spec.rb, but the
# specific end-to-end behaviours (real pool type, live ping through the
# provider lambda, config-mutation side effects that stick post-boot, and the
# failure mode against a closed port) are asserted directly here.
#
# Pairs with the unit spec in spec/unit/onetime/initializers/
# (different agent). This file proves the pipes connect; the unit file proves
# the logic is correct.
RSpec.describe 'SetupConnectionPool (integration)', type: :integration do
  let(:source_config_path) { File.expand_path(File.join(Onetime::HOME, 'spec', 'config.test.yaml')) }

  before(:each) do
    # Reset environment variables that boot reads
    ENV['ONETIME_DEBUG'] = nil

    # Reset Onetime module state (mirrors boot_part2_spec.rb lines 22-36).
    Onetime.instance_variable_set(:@conf, nil)
    Onetime.instance_variable_set(:@mode, :test)
    Onetime.instance_variable_set(:@env, 'test')
    Onetime.instance_variable_set(:@d9s_enabled, nil)
    Onetime.instance_variable_set(:@debug, nil)
    Onetime.instance_variable_set(:@i18n_enabled, nil)
    Onetime.instance_variable_set(:@supported_locales, nil)
    Onetime.instance_variable_set(:@default_locale, nil)
    Onetime.instance_variable_set(:@fallback_locale, nil)
    Onetime.instance_variable_set(:@locale, nil)
    Onetime.instance_variable_set(:@locales, nil)
    Onetime.instance_variable_set(:@instance, nil)
    Onetime.instance_variable_set(:@global_banner, nil)
    OT::Utils.instance_variable_set(:@fortunes, nil)

    # Reset registry and ready state before each test
    Onetime.not_ready

    # Mock Truemail - unrelated to DB but configured during boot
    truemail_config_double = double('Truemail::Configuration').as_null_object
    allow(Truemail).to receive(:configure).and_yield(truemail_config_double)

    # Mock Sentry if defined - also unrelated to DB
    allow(Sentry).to receive(:init).and_return(true) if defined?(Sentry)

    # Use test config
    Onetime::Config.path = source_config_path

    # NOTE: Unlike boot_part2_spec.rb, we do NOT stub `Familia.uri=` here.
    # That spec stubs it because it asserts on global-state flags, not the DB
    # itself. Here the DB connection IS the subject, so we take the real path
    # against Valkey on port 2121.
  end

  after(:each) do
    Onetime.reset_ready!
  end

  describe 'golden path against real Valkey on port 2121' do
    it 'exposes a real ConnectionPool on Onetime::Runtime.infrastructure.database_pool' do
      Onetime.boot!(:test)

      pool = Onetime::Runtime.infrastructure.database_pool
      expect(pool).not_to be_nil
      expect(pool).to be_a(ConnectionPool)
    end

    it 'returns PONG when Familia.connection_provider is invoked end-to-end' do
      Onetime.boot!(:test)

      # Exercise the provider lambda with the real URI - this round-trips through
      # the pool, the Redis client, and the socket to Valkey.
      conn = Familia.connection_provider.call(Familia.uri.to_s)
      expect(conn.ping).to eq('PONG')
    end

    it 'reports database_configured? as true on infrastructure runtime state' do
      Onetime.boot!(:test)

      # NOTE: Familia v2.4 does not expose `database_configured?`. The
      # equivalent predicate lives on Onetime::Runtime::Infrastructure and
      # reflects whether SetupConnectionPool populated the pool slot.
      expect(Onetime::Runtime.infrastructure.database_configured?).to be true
    end

    it 'leaves Familia.transaction_mode set to :warn after boot' do
      Onetime.boot!(:test)

      # The initializer mutates global Familia config. The unit spec mocks
      # Familia.configure; here we prove the side effect is applied against
      # the real global.
      expect(Familia.transaction_mode).to eq(:warn)
    end

    it 'leaves Familia.pipelined_mode set to :warn after boot' do
      Onetime.boot!(:test)

      expect(Familia.pipelined_mode).to eq(:warn)
    end
  end

  describe 'failure mode: URI pointing at a closed port' do
    # Port 1 is IANA-reserved and virtually guaranteed closed on localhost,
    # so connect() returns ECONNREFUSED immediately with no retry wall-clock.
    #
    # ConfigureFamilia enforces a :2121 guard in test mode; we disable that
    # guard by stubbing ENV['RACK_ENV'] so the closed-port URI can reach the
    # pool initializer. A targeted FAMILIA_POOL_TIMEOUT override caps the
    # ceiling in case the reconnect backoff ladder (50ms/200ms/1s/2s per
    # setup_connection_pool.rb lines 52-57) stretches the test runtime.
    around do |example|
      original_timeout = ENV['FAMILIA_POOL_TIMEOUT']
      ENV['FAMILIA_POOL_TIMEOUT'] = '1'
      begin
        example.run
      ensure
        if original_timeout.nil?
          ENV.delete('FAMILIA_POOL_TIMEOUT')
        else
          ENV['FAMILIA_POOL_TIMEOUT'] = original_timeout
        end
      end
    end

    it 'surfaces a connection error rather than silently succeeding' do
      # Load config, then rewrite the URI to a closed port before boot runs.
      # This is cleaner than stubbing VALKEY_URL because config.test.yaml
      # hardcodes the URI without ERB - the ENV var wouldn't propagate.
      OT::Config.before_load
      raw_conf       = OT::Config.load
      processed_conf = OT::Config.after_load(raw_conf)
      processed_conf['redis']['uri'] = 'redis://127.0.0.1:1/0'
      OT.replace_config!(processed_conf)

      # Skip the :2121 test-mode guard in ConfigureFamilia so the closed-port
      # URI reaches the pool initializer. Using RSpec's ENV stubbing rather
      # than mutating real ENV to keep the around-block simple.
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('RACK_ENV').and_return('production')

      # Also skip OT::Config.load during boot so our mutated OT.conf survives.
      allow(OT::Config).to receive(:load).and_return(processed_conf)
      allow(OT::Config).to receive(:after_load).and_return(processed_conf)

      # Exception matching, not message matching - error messages are an
      # unstable contract surface. Redis::CannotConnectError covers
      # ECONNREFUSED from Redis 5.x client; a broader rescue catches driver
      # variations without coupling to them.
      expect {
        Onetime.boot!(:test)
      }.to raise_error(Redis::BaseConnectionError)
    end
  end
end
