# spec/integration/all/initializers/setup_connection_pool_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'connection_pool'
require 'fileutils'
require 'socket'
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
  include OnetimeStateHelpers

  let(:source_config_path) { File.expand_path(File.join(Onetime::HOME, 'spec', 'config.test.yaml')) }

  before(:each) do
    # Reset environment variables that boot reads
    ENV['ONETIME_DEBUG'] = nil

    # Reset Onetime module state via shared helper. The helper keeps the
    # ivar list in one place; see spec/support/helpers/onetime_state_helpers.rb.
    reset_onetime_module_state!

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
    # Strategy for obtaining a guaranteed-closed TCP port: bind a TCPServer
    # to port 0 (OS assigns an ephemeral port), capture the port number, then
    # close the server. For the short window of this test on a single host,
    # the kernel is extremely unlikely to hand the same port to another
    # process. This beats assuming port 1 is closed (which depends on
    # localhost config and privilege rules).
    def ephemeral_closed_port
      server = TCPServer.new('127.0.0.1', 0)
      port   = server.addr[1]
      server.close
      port
    end

    # Snapshot Familia + infrastructure globals around the boot! call. The
    # initializer pipeline partially completes before SetupConnectionPool
    # raises: ConfigureFamilia has already set Familia.uri to the closed-port
    # URI, and SetupConnectionPool has already installed a ConnectionPool +
    # connection_provider targeting that closed port, before Redis.ping
    # fails. Without restoration, subsequent specs (anything going through
    # Familia, e.g. Onetime::BannedIP in the IPBan middleware) route through
    # the leaked provider and hit ECONNREFUSED against the now-reused
    # ephemeral port. FullModeSuiteDatabase.setup! uses an idempotent
    # before(:context) Onetime.boot!, so if it already ran before this
    # example no subsequent boot! rewrites Familia.uri either — the leak
    # sticks across the whole suite.
    #
    # As of the boot.rb datastore guard, boot! now aborts before either
    # mutation happens, so this snapshot/restore is a defensive no-op today.
    # It is kept so the example stays leak-safe if the guard ever moves after
    # the initializer pipeline.
    around do |example|
      snapshot = snapshot_familia_pool_config
      original_timeout = ENV['FAMILIA_POOL_TIMEOUT']
      # FAMILIA_POOL_TIMEOUT caps the wall-clock budget. When connect()
      # returns ECONNREFUSED against a closed localhost port, it returns
      # immediately — the reconnect backoff ladder
      # (setup_connection_pool.rb:52-57) only activates after a successful
      # connection that later drops, so the 1s ceiling here is a defensive
      # floor, not a load-bearing deadline.
      ENV['FAMILIA_POOL_TIMEOUT'] = '1'
      begin
        example.run
      ensure
        if original_timeout.nil?
          ENV.delete('FAMILIA_POOL_TIMEOUT')
        else
          ENV['FAMILIA_POOL_TIMEOUT'] = original_timeout
        end
        restore_familia_pool_config(snapshot)
      end
    end

    it 'is blocked by the test-datastore guard before it can touch a bad datastore' do
      closed_port = ephemeral_closed_port

      # Load config, then rewrite the URI to a closed, non-:2121 port before
      # boot runs. This is cleaner than stubbing VALKEY_URL because
      # config.test.yaml hardcodes the URI without ERB - the ENV var wouldn't
      # propagate. OT::Config.after_load would deep_freeze the returned hash if
      # OT.testing? were false; it stays true here (boot!(:test) sets the mode),
      # so the mutation-after-after_load path continues to work.
      OT::Config.before_load
      raw_conf       = OT::Config.load
      processed_conf = OT::Config.after_load(raw_conf)
      processed_conf['redis']['uri'] = "redis://127.0.0.1:#{closed_port}/0"
      OT.replace_config!(processed_conf)

      # Skip OT::Config.load during boot so our mutated OT.conf survives.
      allow(OT::Config).to receive(:load).and_return(processed_conf)
      allow(OT::Config).to receive(:after_load).and_return(processed_conf)

      # boot!(:test) against a non-:2121 datastore now fails closed at the
      # boot.rb datastore guard (added in "Enforce datastore safety for tests
      # and tryouts", boot.rb:161, keyed on OT.mode?(:test)) BEFORE any
      # initializer runs — so the connection pool is never built and Familia.uri
      # is never rewritten. This guard supersedes the old ECONNREFUSED-at-the-
      # pool path: the boot still surfaces the error loudly, just at an earlier,
      # stronger gate. Match the guard message so an unrelated Onetime::Problem
      # can't masquerade as a pass.
      expect {
        Onetime.boot!(:test)
      }.to raise_error(Onetime::Problem, /test datastore/)
    end
  end
end
