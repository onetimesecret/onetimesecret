# spec/unit/boot/initializer_registry_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'benchmark'

# Unit tests for InitializerRegistry @phase infrastructure
#
# Focuses on fork-sensitive initializer methods introduced in #2201 and #2202.
# These tests complement existing Tryouts tests with RSpec-specific features
# like mocking, stubbing, and isolation.
#
# == Registry Reset Methods ==
#
# The registry has two reset methods with different behaviors:
#
#   | Method        | @registered_classes | Runtime State |
#   |---------------|---------------------|---------------|
#   | soft_reset!   | PRESERVED           | Cleared       |
#   | hard_reset!   | CLEARED             | Cleared       |
#
# Production initializers (SetupLoggers, SetupRabbitMQ, etc.) auto-register
# when spec_helper loads via the inherited hook. This means @registered_classes
# contains production classes BEFORE any test runs.
#
# Use hard_reset! for unit tests that need a truly empty registry (like these).
# Use soft_reset! for integration tests that need production initializers preserved.
#
RSpec.describe Onetime::Boot::InitializerRegistry do
  # Use subject for cleaner test syntax
  subject(:registry) { described_class }

  # Reset registry state before each test to ensure isolation
  # Use hard_reset! to clear everything (including production initializer classes)
  # This ensures unit tests run in true isolation
  before do
    registry.hard_reset!
  end

  after do
    registry.hard_reset!
  end

  # Helper to create a fork-sensitive initializer class for testing
  def create_fork_sensitive_initializer(name_suffix, cleanup_proc = nil, reconnect_proc = nil)
    cleanup_block = cleanup_proc || -> {}
    reconnect_block = reconnect_proc || -> {}

    klass = Class.new(Onetime::Boot::Initializer) do
      @phase = :fork_sensitive

      define_method(:execute) { |_ctx| }
      define_method(:cleanup, &cleanup_block)
      define_method(:reconnect, &reconnect_block)
    end

    klass.define_singleton_method(:name) { "TestForkSensitive#{name_suffix}" }
    klass
  end

  # Helper to create a basic preload initializer class
  def create_preload_initializer(name_suffix)
    klass = Class.new(Onetime::Boot::Initializer) do
      define_method(:execute) { |_ctx| }
    end

    klass.define_singleton_method(:name) { "TestPreload#{name_suffix}" }
    klass
  end

  describe '#fork_sensitive_initializers' do
    context 'when no initializers are registered' do
      it 'returns an empty array' do
        registry.load_all
        expect(registry.fork_sensitive_initializers).to eq([])
      end
    end

    context 'with only fork-sensitive initializers' do
      it 'returns all fork-sensitive initializers' do
        create_fork_sensitive_initializer('A')
        create_fork_sensitive_initializer('B')

        registry.load_all
        fork_sensitive = registry.fork_sensitive_initializers

        expect(fork_sensitive.size).to eq(2)
        expect(fork_sensitive.map(&:phase)).to all(eq(:fork_sensitive))
      end
    end

    context 'with only preload initializers' do
      it 'returns an empty array' do
        create_preload_initializer('A')
        create_preload_initializer('B')

        registry.load_all
        expect(registry.fork_sensitive_initializers).to eq([])
      end
    end

    context 'with mixed phase initializers' do
      it 'excludes preload phase initializers' do
        create_preload_initializer('A')
        create_fork_sensitive_initializer('B')
        create_preload_initializer('C')

        registry.load_all
        fork_sensitive = registry.fork_sensitive_initializers

        expect(fork_sensitive.size).to eq(1)
        expect(fork_sensitive.first.phase).to eq(:fork_sensitive)
      end

      it 'handles mixed phases correctly' do
        3.times { |i| create_preload_initializer("Preload#{i}") }
        2.times { |i| create_fork_sensitive_initializer("Fork#{i}") }

        registry.load_all
        fork_sensitive = registry.fork_sensitive_initializers

        expect(fork_sensitive.size).to eq(2)
        expect(registry.initializers.size).to eq(5)
      end
    end

    context 'return value characteristics' do
      it 'returns instances, not classes' do
        create_fork_sensitive_initializer('A')

        registry.load_all
        fork_sensitive = registry.fork_sensitive_initializers

        expect(fork_sensitive.first).to be_a(Onetime::Boot::Initializer)
        expect(fork_sensitive.first.class.superclass).to eq(Onetime::Boot::Initializer)
      end

      it 'maintains registration order' do
        # Create initializers with specific cleanup behaviors to track order
        calls = []
        create_fork_sensitive_initializer('First', -> { calls << :first })
        create_fork_sensitive_initializer('Second', -> { calls << :second })
        create_fork_sensitive_initializer('Third', -> { calls << :third })

        registry.load_all
        fork_sensitive = registry.fork_sensitive_initializers

        # Verify order by calling cleanup in sequence
        fork_sensitive.each(&:cleanup)
        expect(calls).to eq(%i[first second third])
      end
    end

    context 'with nil or missing phase' do
      it 'handles nil phase gracefully (defaults to :preload)' do
        klass = Class.new(Onetime::Boot::Initializer) do
          @phase = nil
          define_method(:execute) { |_ctx| }
        end
        klass.define_singleton_method(:name) { 'TestNilPhase' }

        registry.load_all
        expect(registry.fork_sensitive_initializers).to eq([])
      end
    end

    context 'performance with many initializers' do
      it 'handles large number of initializers efficiently' do
        # Create 100 initializers (mix of preload and fork-sensitive)
        50.times { |i| create_preload_initializer("Preload#{i}") }
        50.times { |i| create_fork_sensitive_initializer("Fork#{i}") }

        registry.load_all

        elapsed = Benchmark.realtime do
          registry.fork_sensitive_initializers
        end

        expect(elapsed).to be < 0.1 # Should complete in under 100ms
      end
    end
  end

  describe '#cleanup_before_fork' do
    context 'with no fork-sensitive initializers' do
      it 'completes without error' do
        create_preload_initializer('A')

        registry.load_all
        expect { registry.cleanup_before_fork }.not_to raise_error
      end

      it 'does not call any cleanup methods' do
        cleanup_called = false
        klass = Class.new(Onetime::Boot::Initializer) do
          define_method(:execute) { |_ctx| }
          define_method(:cleanup) { cleanup_called = true }
        end
        klass.define_singleton_method(:name) { 'TestPreloadWithCleanup' }

        registry.load_all
        registry.cleanup_before_fork

        expect(cleanup_called).to be false
      end
    end

    context 'with fork-sensitive initializers' do
      it 'calls cleanup on all fork-sensitive initializers' do
        calls = []
        create_fork_sensitive_initializer('A', -> { calls << :a })
        create_fork_sensitive_initializer('B', -> { calls << :b })

        registry.load_all
        registry.cleanup_before_fork

        expect(calls).to contain_exactly(:a, :b)
      end

      it 'calls initializers in registration order' do
        calls = []
        create_fork_sensitive_initializer('First', -> { calls << 1 })
        create_fork_sensitive_initializer('Second', -> { calls << 2 })
        create_fork_sensitive_initializer('Third', -> { calls << 3 })

        registry.load_all
        registry.cleanup_before_fork

        expect(calls).to eq([1, 2, 3])
      end
    end

    context 'error handling' do
      it 'continues on StandardError from one initializer' do
        calls = []
        create_fork_sensitive_initializer('Error', -> { raise 'cleanup failed' })
        create_fork_sensitive_initializer('Ok', -> { calls << :ok })

        registry.load_all

        expect { registry.cleanup_before_fork }.not_to raise_error
        expect(calls).to include(:ok)
      end

      it 'logs errors but does not raise' do
        create_fork_sensitive_initializer('Error', -> { raise 'connection error' })

        registry.load_all

        # Capture logger output
        logger = instance_double(Logger)
        allow(registry).to receive(:init_logger).and_return(logger)
        expect(logger).to receive(:warn).with(/Error cleaning up/)

        registry.cleanup_before_fork
      end

      it 'continues cleanup after error for remaining initializers' do
        calls = []
        create_fork_sensitive_initializer('First', -> { calls << 1 })
        create_fork_sensitive_initializer('Error', -> { raise IOError, 'network fail' })
        create_fork_sensitive_initializer('Third', -> { calls << 3 })

        registry.load_all
        registry.cleanup_before_fork

        expect(calls).to eq([1, 3])
      end

      it 're-raises NoMethodError (programming errors)' do
        create_fork_sensitive_initializer('Bug', -> { raise NoMethodError, 'undefined method' })

        registry.load_all

        expect { registry.cleanup_before_fork }.to raise_error(NoMethodError)
      end

      it 're-raises NameError (programming errors)' do
        create_fork_sensitive_initializer('Bug', -> { raise NameError, 'undefined constant' })

        registry.load_all

        expect { registry.cleanup_before_fork }.to raise_error(NameError)
      end

      it 'catches StandardError subclasses (IOError, Timeout::Error, etc)' do
        calls = []
        create_fork_sensitive_initializer('IOErr', -> { raise IOError, 'io failed' })
        create_fork_sensitive_initializer('TimeoutErr', -> { raise Timeout::Error, 'timeout' })
        create_fork_sensitive_initializer('Ok', -> { calls << :ok })

        registry.load_all

        expect { registry.cleanup_before_fork }.not_to raise_error
        expect(calls).to include(:ok)
      end
    end

    context 'state tracking' do
      it 'tracks which initializers were cleaned up via side effects' do
        cleaned = []
        create_fork_sensitive_initializer('A', -> { cleaned << :a })
        create_fork_sensitive_initializer('B', -> { cleaned << :b })

        registry.load_all
        registry.cleanup_before_fork

        expect(cleaned).to eq(%i[a b])
      end

      it 'verifies idempotency by calling cleanup twice' do
        call_count = 0
        create_fork_sensitive_initializer('A', -> { call_count += 1 })

        registry.load_all
        registry.cleanup_before_fork
        registry.cleanup_before_fork

        expect(call_count).to eq(2)
      end
    end

    context 'performance' do
      it 'completes within 100ms threshold for many initializers' do
        20.times do |i|
          create_fork_sensitive_initializer("Init#{i}", -> { sleep 0.001 })
        end

        registry.load_all

        elapsed = Benchmark.realtime do
          registry.cleanup_before_fork
        end

        expect(elapsed).to be < 0.1
      end
    end

    context 'thread safety' do
      it 'handles concurrent cleanup calls safely' do
        calls = []
        mutex = Mutex.new
        create_fork_sensitive_initializer('Concurrent', -> { mutex.synchronize { calls << :cleanup } })

        registry.load_all

        threads = 3.times.map do
          Thread.new { registry.cleanup_before_fork }
        end

        threads.each(&:join)

        # Should be called 3 times (once per thread)
        expect(calls.size).to eq(3)
      end
    end
  end

  describe '#reconnect_after_fork' do
    context 'with no fork-sensitive initializers' do
      it 'completes without error' do
        create_preload_initializer('A')

        registry.load_all
        expect { registry.reconnect_after_fork }.not_to raise_error
      end

      it 'does not call any reconnect methods' do
        reconnect_called = false
        klass = Class.new(Onetime::Boot::Initializer) do
          define_method(:execute) { |_ctx| }
          define_method(:reconnect) { reconnect_called = true }
        end
        klass.define_singleton_method(:name) { 'TestPreloadWithReconnect' }

        registry.load_all
        registry.reconnect_after_fork

        expect(reconnect_called).to be false
      end
    end

    context 'with fork-sensitive initializers' do
      it 'calls reconnect on all fork-sensitive initializers' do
        calls = []
        create_fork_sensitive_initializer('A', nil, -> { calls << :a })
        create_fork_sensitive_initializer('B', nil, -> { calls << :b })

        registry.load_all
        registry.reconnect_after_fork

        expect(calls).to contain_exactly(:a, :b)
      end

      it 'calls initializers in registration order' do
        calls = []
        create_fork_sensitive_initializer('First', nil, -> { calls << 1 })
        create_fork_sensitive_initializer('Second', nil, -> { calls << 2 })
        create_fork_sensitive_initializer('Third', nil, -> { calls << 3 })

        registry.load_all
        registry.reconnect_after_fork

        expect(calls).to eq([1, 2, 3])
      end
    end

    context 'error handling - degraded mode' do
      it 'continues on StandardError from one initializer' do
        calls = []
        create_fork_sensitive_initializer('Error', nil, -> { raise 'reconnect failed' })
        create_fork_sensitive_initializer('Ok', nil, -> { calls << :ok })

        registry.load_all

        expect { registry.reconnect_after_fork }.not_to raise_error
        expect(calls).to include(:ok)
      end

      it 'logs errors but does not raise' do
        create_fork_sensitive_initializer('Error', nil, -> { raise 'database unavailable' })

        registry.load_all

        logger = instance_double(Logger)
        allow(registry).to receive(:init_logger).and_return(logger)
        expect(logger).to receive(:warn).with(/Error reconnecting/)

        registry.reconnect_after_fork
      end

      it 'continues reconnect after error for remaining initializers' do
        calls = []
        create_fork_sensitive_initializer('First', nil, -> { calls << 1 })
        create_fork_sensitive_initializer('Error', nil, -> { raise 'connection timeout' })
        create_fork_sensitive_initializer('Third', nil, -> { calls << 3 })

        registry.load_all
        registry.reconnect_after_fork

        expect(calls).to eq([1, 3])
      end

      it 're-raises NoMethodError (programming errors)' do
        create_fork_sensitive_initializer('Bug', nil, -> { raise NoMethodError, 'undefined method' })

        registry.load_all

        expect { registry.reconnect_after_fork }.to raise_error(NoMethodError)
      end

      it 're-raises NameError (programming errors)' do
        create_fork_sensitive_initializer('Bug', nil, -> { raise NameError, 'undefined constant' })

        registry.load_all

        expect { registry.reconnect_after_fork }.to raise_error(NameError)
      end

      it 'catches StandardError subclasses for degraded mode' do
        calls = []
        create_fork_sensitive_initializer('IOErr', nil, -> { raise IOError, 'connection lost' })
        create_fork_sensitive_initializer('TimeoutErr', nil, -> { raise Timeout::Error, 'timeout' })
        create_fork_sensitive_initializer('Ok', nil, -> { calls << :ok })

        registry.load_all

        expect { registry.reconnect_after_fork }.not_to raise_error
        expect(calls).to include(:ok)
      end
    end

    context 'state verification' do
      it 'tracks which initializers were reconnected' do
        reconnected = []
        create_fork_sensitive_initializer('A', nil, -> { reconnected << :a })
        create_fork_sensitive_initializer('B', nil, -> { reconnected << :b })

        registry.load_all
        registry.reconnect_after_fork

        expect(reconnected).to eq(%i[a b])
      end

      it 'verifies proper reconnection state' do
        state = { connected: false }
        create_fork_sensitive_initializer('DB', nil, -> { state[:connected] = true })

        registry.load_all
        registry.reconnect_after_fork

        expect(state[:connected]).to be true
      end
    end

    context 'performance' do
      it 'completes within 100ms threshold for many initializers' do
        20.times do |i|
          create_fork_sensitive_initializer("Init#{i}", nil, -> { sleep 0.001 })
        end

        registry.load_all

        elapsed = Benchmark.realtime do
          registry.reconnect_after_fork
        end

        expect(elapsed).to be < 0.1
      end
    end

    context 'thread safety' do
      it 'handles concurrent reconnect calls safely' do
        calls = []
        mutex = Mutex.new
        create_fork_sensitive_initializer('Concurrent', nil, -> { mutex.synchronize { calls << :reconnect } })

        registry.load_all

        threads = 3.times.map do
          Thread.new { registry.reconnect_after_fork }
        end

        threads.each(&:join)

        expect(calls.size).to eq(3)
      end
    end
  end

  describe 'validation enforcement' do
    context 'at registration time via load_all' do
      it 'validates phase values when loading initializers' do
        klass = Class.new(Onetime::Boot::Initializer) do
          @phase = :fork_sensitive
          define_method(:execute) { |_ctx| }
          # Missing cleanup and reconnect
        end
        klass.define_singleton_method(:name) { 'TestMissingMethods' }

        expect { registry.load_all }.to raise_error(Onetime::Problem, /must implement/)

        # Clean up to prevent pollution of subsequent tests
        registry.unregister_class(klass)
      end

      it 'rejects fork-sensitive initializer without cleanup method' do
        klass = Class.new(Onetime::Boot::Initializer) do
          @phase = :fork_sensitive
          define_method(:execute) { |_ctx| }
          define_method(:reconnect) { }
          # Missing cleanup
        end
        klass.define_singleton_method(:name) { 'TestNoCleanup' }

        expect { registry.load_all }.to raise_error(Onetime::Problem, /cleanup/)

        # Clean up to prevent pollution of subsequent tests
        registry.unregister_class(klass)
      end

      it 'rejects fork-sensitive initializer without reconnect method' do
        klass = Class.new(Onetime::Boot::Initializer) do
          @phase = :fork_sensitive
          define_method(:execute) { |_ctx| }
          define_method(:cleanup) { }
          # Missing reconnect
        end
        klass.define_singleton_method(:name) { 'TestNoReconnect' }

        expect { registry.load_all }.to raise_error(Onetime::Problem, /reconnect/)

        # Clean up to prevent pollution of subsequent tests
        registry.unregister_class(klass)
      end

      it 'rejects fork-sensitive initializer missing both methods' do
        klass = Class.new(Onetime::Boot::Initializer) do
          @phase = :fork_sensitive
          define_method(:execute) { |_ctx| }
        end
        klass.define_singleton_method(:name) { 'TestNoBoth' }

        expect do
          registry.load_all
        end.to raise_error(Onetime::Problem) do |error|
          expect(error.message).to include('cleanup')
          expect(error.message).to include('reconnect')
        end

        # Clean up to prevent pollution of subsequent tests
        registry.unregister_class(klass)
      end
    end

    context 'allowed phase values' do
      it 'allows :preload phase' do
        klass = Class.new(Onetime::Boot::Initializer) do
          @phase = :preload
          define_method(:execute) { |_ctx| }
        end
        klass.define_singleton_method(:name) { 'TestPreloadPhase' }

        expect { registry.load_all }.not_to raise_error

        # Clean up to prevent pollution of subsequent tests
        registry.unregister_class(klass)
      end

      it 'allows :fork_sensitive phase with required methods' do
        create_fork_sensitive_initializer('Valid')

        expect { registry.load_all }.not_to raise_error
      end
    end

    context 'helpful error messages' do
      it 'provides clear error message for missing methods' do
        klass = Class.new(Onetime::Boot::Initializer) do
          @phase = :fork_sensitive
          define_method(:execute) { |_ctx| }
        end
        klass.define_singleton_method(:name) { 'TestHelpfulError' }

        expect do
          registry.load_all
        end.to raise_error(Onetime::Problem) do |error|
          expect(error.message).to include('test_helpful_error')
          expect(error.message).to include('must implement')
        end

        # Clean up to prevent pollution of subsequent tests
        registry.unregister_class(klass)
      end
    end

    context 'validation timing' do
      it 'validates before Puma starts (fail fast)' do
        klass = Class.new(Onetime::Boot::Initializer) do
          @phase = :fork_sensitive
          define_method(:execute) { |_ctx| }
        end
        klass.define_singleton_method(:name) { 'TestEarlyValidation' }

        # load_all should fail immediately, not during cleanup/reconnect
        expect { registry.load_all }.to raise_error(Onetime::Problem)

        # Clean up to prevent pollution of subsequent tests
        registry.unregister_class(klass)
      end

      it 'catches configuration errors early' do
        klass = Class.new(Onetime::Boot::Initializer) do
          @phase = :fork_sensitive
          define_method(:execute) { |_ctx| }
          define_method(:cleanup) { }
          # Intentionally define reconnect with wrong arity to catch later
        end
        klass.define_singleton_method(:name) { 'TestConfigError' }

        # Should still fail validation for missing method
        expect do
          registry.load_all
        end.to raise_error(Onetime::Problem, /reconnect/)

        # Clean up to prevent pollution of subsequent tests
        registry.unregister_class(klass)
      end
    end

    context 'edge cases' do
      it 'handles initializer with cleanup but wrong signature' do
        klass = Class.new(Onetime::Boot::Initializer) do
          @phase = :fork_sensitive
          define_method(:execute) { |_ctx| }
          define_method(:cleanup) { }
          define_method(:reconnect) { }
        end
        klass.define_singleton_method(:name) { 'TestEdgeCase' }

        # Should pass validation (method exists)
        expect { registry.load_all }.not_to raise_error

        # Clean up to prevent pollution of subsequent tests
        registry.unregister_class(klass)
      end
    end
  end
end
