# spec/unit/onetime/initializers/setup_connection_pool_spec.rb
#
# frozen_string_literal: true

# SetupConnectionPool Initializer Unit Tests
#
# These tests verify the connection-pool initializer's direct behaviour:
# - Guard against booting before Familia models are loaded
# - Environment variable parsing for pool size/timeout
# - ConnectionPool instantiation arguments
# - Familia.configure side-effects (transaction_mode, pipelined_mode, connection_provider)
# - connection_provider lambda shape (delegates via pool.with)
# - Runtime.update_infrastructure receives the constructed pool
#
# Fork safety, ConnectionPool internals, log content, Redis.new deep argument
# shape, and end-to-end ping are covered elsewhere (see puma_initializer_fork_spec.rb,
# fork_hooks_thread_safety_spec.rb, and the integration spec for this initializer).
#
# Run with (standard Ruby): bundle exec rspec spec/unit/onetime/initializers/setup_connection_pool_spec.rb
# Or, if your project uses a pnpm wrapper: pnpm run test:rspec spec/unit/onetime/initializers/setup_connection_pool_spec.rb

require 'spec_helper'

# rubocop:disable RSpec/SpecFilePathFormat
# File name matches implementation file setup_connection_pool.rb
RSpec.describe Onetime::Initializers::SetupConnectionPool do
  include OnetimeStateHelpers

  let(:instance) { described_class.new }

  # Reusable doubles that stand in for the boundary collaborators. The pool
  # yields the redis connection when .with is called; the redis double only
  # needs to respond to .ping for the connectivity check in the initializer.
  let(:mock_redis) { instance_double(Redis, ping: 'PONG') }
  let(:mock_pool) { instance_double(ConnectionPool) }

  # Minimal stand-in for Familia.members entries. The initializer only calls
  # .to_s and .size on the collection, so any object responding to to_s works.
  let(:fake_member) { Class.new { def self.to_s; 'FakeModel'; end } }

  # Snapshot/restore Familia + Runtime state around each example. The around
  # hook guarantees restoration even when an expectation raises. Uses public
  # Familia setters via the shared helper; see onetime_state_helpers.rb for
  # the nil-vs-symbol nuance on transaction_mode / pipelined_mode.
  around do |example|
    original_infrastructure = Onetime::Runtime.infrastructure
    familia_snapshot        = snapshot_familia_pool_config
    begin
      example.run
    ensure
      Onetime::Runtime.infrastructure = original_infrastructure
      restore_familia_pool_config(familia_snapshot)
    end
  end

  before do
    # Default: pretend at least one model is loaded, so the empty-members guard
    # does not trip. Individual examples override with [] where they want to
    # assert the raise path.
    allow(Familia).to receive(:members).and_return([fake_member])

    # Default: a plausible Familia URI is configured. Individual examples that
    # need specific URI behaviour will re-stub.
    allow(Familia).to receive(:uri).and_return(URI.parse('redis://127.0.0.1:6379/0'))
    allow(Familia).to receive(:normalize_uri) do |uri|
      uri.is_a?(URI) ? uri : URI.parse(uri.to_s)
    end

    # Default pool/Redis stubs so the happy-path tests don't all have to repeat
    # them. Examples that want to assert on ConnectionPool.new arguments can
    # still override with expect(...).
    allow(ConnectionPool).to receive(:new).and_return(mock_pool)
    allow(mock_pool).to receive(:with).and_yield(mock_redis)
    allow(Redis).to receive(:new).and_return(mock_redis)

    # Keep the log output out of the test runner.
    allow(OT).to receive(:ld)
    allow(OT).to receive(:log_box)
  end

  describe 'Familia.members guard' do
    # Stubbing Familia.members keeps the test fast; a subprocess test is
    # possible but overkill for a single-line raise guard.
    context 'when no Familia members are loaded' do
      before do
        allow(Familia).to receive(:members).and_return([])
      end

      it 'raises Onetime::Problem with a descriptive message' do
        expect { instance.execute(nil) }.to raise_error(
          Onetime::Problem,
          'No known Familia members. Models need to load before boot!',
        )
      end

      it 'does not construct a ConnectionPool' do
        expect(ConnectionPool).not_to receive(:new)
        expect { instance.execute(nil) }.to raise_error(Onetime::Problem)
      end
    end

    context 'when at least one Familia member is loaded' do
      it 'does not raise' do
        expect { instance.execute(nil) }.not_to raise_error
      end
    end
  end

  describe 'FAMILIA_POOL_SIZE / FAMILIA_POOL_TIMEOUT environment variables' do
    around do |example|
      original_size    = ENV['FAMILIA_POOL_SIZE']
      original_timeout = ENV['FAMILIA_POOL_TIMEOUT']
      example.run
    ensure
      if original_size.nil?
        ENV.delete('FAMILIA_POOL_SIZE')
      else
        ENV['FAMILIA_POOL_SIZE'] = original_size
      end
      if original_timeout.nil?
        ENV.delete('FAMILIA_POOL_TIMEOUT')
      else
        ENV['FAMILIA_POOL_TIMEOUT'] = original_timeout
      end
    end

    context 'when both env vars are unset' do
      before do
        ENV.delete('FAMILIA_POOL_SIZE')
        ENV.delete('FAMILIA_POOL_TIMEOUT')
      end

      it 'defaults size to 25 and timeout to 5' do
        expect(ConnectionPool).to receive(:new)
          .with(hash_including(size: 25, timeout: 5))
          .and_return(mock_pool)
        instance.execute(nil)
      end
    end

    context 'when both env vars are set to valid integer strings' do
      before do
        ENV['FAMILIA_POOL_SIZE']    = '50'
        ENV['FAMILIA_POOL_TIMEOUT'] = '10'
      end

      it 'uses the parsed integer values' do
        expect(ConnectionPool).to receive(:new)
          .with(hash_including(size: 50, timeout: 10))
          .and_return(mock_pool)
        instance.execute(nil)
      end
    end

    context 'when env vars are set to non-numeric strings (characterization)' do
      # Characterization test: documents current behaviour. String#to_i on a
      # non-numeric value returns 0, which produces an unusable ConnectionPool
      # (size: 0 checkouts always fail). Validation is a separate concern;
      # this test pins the behaviour so a future change is a deliberate choice,
      # not an accident.
      before do
        ENV['FAMILIA_POOL_SIZE']    = 'abc'
        ENV['FAMILIA_POOL_TIMEOUT'] = 'xyz'
      end

      it 'coerces non-numeric values to 0 via String#to_i' do
        expect(ConnectionPool).to receive(:new)
          .with(hash_including(size: 0, timeout: 0))
          .and_return(mock_pool)
        instance.execute(nil)
      end
    end

    context 'when env vars are empty strings (characterization)' do
      # ENV.fetch returns the empty string (not the default), and ''.to_i is 0.
      # Same failure shape as 'abc'/'xyz' but via a different mechanism — worth
      # pinning separately since the fetch default branch is skipped.
      before do
        ENV['FAMILIA_POOL_SIZE']    = ''
        ENV['FAMILIA_POOL_TIMEOUT'] = ''
      end

      it 'coerces empty strings to 0 via String#to_i' do
        expect(ConnectionPool).to receive(:new)
          .with(hash_including(size: 0, timeout: 0))
          .and_return(mock_pool)
        instance.execute(nil)
      end
    end

    context 'when env vars are negative integer strings (characterization)' do
      # The initializer passes the parsed integers through to ConnectionPool.new
      # without range validation. ConnectionPool itself may reject at runtime,
      # but that's not this initializer's concern.
      before do
        ENV['FAMILIA_POOL_SIZE']    = '-5'
        ENV['FAMILIA_POOL_TIMEOUT'] = '-1'
      end

      it 'passes negative integers through unchanged' do
        expect(ConnectionPool).to receive(:new)
          .with(hash_including(size: -5, timeout: -1))
          .and_return(mock_pool)
        instance.execute(nil)
      end
    end

    context 'when env vars are very large integer strings (characterization)' do
      # Ruby Integer is bignum-capable; no overflow. The point of this test is
      # to prove the initializer does no capping or truncation of its own.
      before do
        ENV['FAMILIA_POOL_SIZE']    = '1000000000'
        ENV['FAMILIA_POOL_TIMEOUT'] = '999999999'
      end

      it 'passes large integers through unchanged' do
        expect(ConnectionPool).to receive(:new)
          .with(hash_including(size: 1_000_000_000, timeout: 999_999_999))
          .and_return(mock_pool)
        instance.execute(nil)
      end
    end
  end

  describe 'ConnectionPool construction' do
    it 'invokes ConnectionPool.new with size, timeout, and reconnect_attempts' do
      expect(ConnectionPool).to receive(:new)
        .with(hash_including(size: 25, timeout: 5, reconnect_attempts: 4))
        .and_return(mock_pool)
      instance.execute(nil)
    end

    it 'constructs the pool exactly once' do
      expect(ConnectionPool).to receive(:new).once.and_return(mock_pool)
      instance.execute(nil)
    end
  end

  describe 'Familia.configure side-effects' do
    it 'sets transaction_mode to :warn' do
      instance.execute(nil)
      expect(Familia.transaction_mode).to eq(:warn)
    end

    it 'sets pipelined_mode to :warn' do
      instance.execute(nil)
      expect(Familia.pipelined_mode).to eq(:warn)
    end

    it 'installs a connection_provider lambda' do
      instance.execute(nil)
      expect(Familia.connection_provider).to respond_to(:call)
    end
  end

  describe 'connection_provider lambda shape' do
    it 'yields via pool.with and returns the checked-out connection' do
      instance.execute(nil)

      provider = Familia.connection_provider
      # The lambda ignores its argument and delegates to database_pool.with,
      # returning whatever the block yields. With our stubbed pool, .with
      # yields mock_redis, so that's what the provider should return.
      result = provider.call('redis://ignored')

      expect(mock_pool).to have_received(:with).at_least(:once)
      expect(result).to eq(mock_redis)
    end

    it 'can be invoked multiple times' do
      instance.execute(nil)

      provider = Familia.connection_provider
      3.times { provider.call(nil) }

      # Once inside setup (the ping), plus three provider invocations.
      expect(mock_pool).to have_received(:with).at_least(4).times
    end

    it 'propagates errors raised by pool.with' do
      # Characterization: the provider is a thin delegation. It does not
      # rescue. If pool.with raises (e.g. ConnectionPool::TimeoutError,
      # ConnectionPool::Error::ConnectionNotEstablished), that error surfaces
      # to the Familia caller.
      instance.execute(nil)

      allow(mock_pool).to receive(:with)
        .and_raise(ConnectionPool::TimeoutError, 'Waited 5 sec')

      provider = Familia.connection_provider
      expect { provider.call(nil) }.to raise_error(ConnectionPool::TimeoutError)
    end
  end

  describe 'Runtime.update_infrastructure' do
    it 'updates the infrastructure with the constructed pool' do
      expect(Onetime::Runtime).to receive(:update_infrastructure)
        .with(database_pool: mock_pool)
      instance.execute(nil)
    end

    it 'makes the pool available via Onetime::Runtime.infrastructure.database_pool' do
      instance.execute(nil)
      expect(Onetime::Runtime.infrastructure.database_pool).to eq(mock_pool)
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
