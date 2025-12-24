# spec/performance/initializer_registry_performance_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'benchmark'

# Performance benchmark tests for InitializerRegistry @phase infrastructure
#
# These tests establish performance baselines for registry operations,
# particularly fork-sensitive cleanup and reconnect operations that run
# in Puma's before_fork and after_fork hooks.
#
# Performance targets:
# - cleanup_before_fork: <100ms for 10 initializers, <200ms for 50
# - reconnect_after_fork: <100ms for 10 initializers, <200ms for 50
# - Registry operations maintain efficient baseline under normal load
#
RSpec.describe Onetime::Boot::InitializerRegistry, :performance do
  # Fresh registry instance for each test (pure DI - no global state)
  let(:registry) { described_class.new }

  # Helper to create a minimal fork-sensitive initializer
  # No actual I/O to ensure tests measure registry overhead, not external operations
  def create_fork_sensitive_initializer(name_suffix)
    klass = Class.new(Onetime::Boot::Initializer) do
      @phase = :fork_sensitive

      define_method(:execute) { |_ctx| }

      # Minimal cleanup with negligible overhead (<1μs)
      define_method(:cleanup) do
        @cleaned = true
      end

      # Minimal reconnect with negligible overhead (<1μs)
      define_method(:reconnect) do
        @reconnected = true
      end
    end

    klass.define_singleton_method(:name) { "PerfTest#{name_suffix}" }
    klass
  end

  describe '#cleanup_before_fork performance' do
    context 'with 10 fork-sensitive initializers' do
      it 'completes within 100ms threshold' do
        # Create 10 minimal fork-sensitive initializers
        classes = []
        10.times { |i| classes << create_fork_sensitive_initializer("Cleanup10_#{i}") }

        registry.load_only(classes)

        # Measure cleanup performance
        elapsed = Benchmark.realtime do
          registry.cleanup_before_fork
        end

        # Performance expectation: <100ms for 10 initializers
        # This accounts for method dispatch overhead, iteration, and error handling
        expect(elapsed).to be < 0.1
      end
    end

    context 'with 50 fork-sensitive initializers' do
      it 'completes within 200ms threshold' do
        # Create 50 minimal fork-sensitive initializers
        classes = []
        50.times { |i| classes << create_fork_sensitive_initializer("Cleanup50_#{i}") }

        registry.load_only(classes)

        # Measure cleanup performance
        elapsed = Benchmark.realtime do
          registry.cleanup_before_fork
        end

        # Performance expectation: <200ms for 50 initializers
        # Linear scaling from 10 initializer baseline with safety margin
        expect(elapsed).to be < 0.2
      end
    end
  end

  describe '#reconnect_after_fork performance' do
    context 'with 10 fork-sensitive initializers' do
      it 'completes within 100ms threshold' do
        # Create 10 minimal fork-sensitive initializers
        classes = []
        10.times { |i| classes << create_fork_sensitive_initializer("Reconnect10_#{i}") }

        registry.load_only(classes)

        # Measure reconnect performance
        elapsed = Benchmark.realtime do
          registry.reconnect_after_fork
        end

        # Performance expectation: <100ms for 10 initializers
        # This accounts for method dispatch overhead, iteration, and error handling
        expect(elapsed).to be < 0.1
      end
    end

    context 'with 50 fork-sensitive initializers' do
      it 'completes within 200ms threshold' do
        # Create 50 minimal fork-sensitive initializers
        classes = []
        50.times { |i| classes << create_fork_sensitive_initializer("Reconnect50_#{i}") }

        registry.load_only(classes)

        # Measure reconnect performance
        elapsed = Benchmark.realtime do
          registry.reconnect_after_fork
        end

        # Performance expectation: <200ms for 50 initializers
        # Linear scaling from 10 initializer baseline with safety margin
        expect(elapsed).to be < 0.2
      end
    end
  end

  describe 'registry operations baseline performance' do
    it 'maintains efficient happy path under normal load' do
      # Create realistic mixed workload:
      # - 5 preload phase initializers (typical: config, logging, etc)
      # - 5 fork-sensitive initializers (typical: DB, Redis, HTTP clients)
      classes = []

      5.times do |i|
        preload_klass = Class.new(Onetime::Boot::Initializer) do
          define_method(:execute) { |_ctx| }
        end
        preload_klass.define_singleton_method(:name) { "PreloadPerf#{i}" }
        classes << preload_klass
      end

      5.times { |i| classes << create_fork_sensitive_initializer("ForkPerf#{i}") }

      # Measure load_all performance (dependency resolution + validation)
      load_elapsed = Benchmark.realtime do
        registry.load_only(classes)
      end

      # Measure fork_sensitive_initializers filtering performance
      filter_elapsed = Benchmark.realtime do
        registry.fork_sensitive_initializers
      end

      # Performance expectations for happy path:
      # - load_all (dependency resolution + validation): <50ms
      # - fork_sensitive_initializers (filtering): <10ms
      #
      # These establish baseline performance metrics for typical boot scenarios
      expect(load_elapsed).to be < 0.05,
        "load_all should complete in <50ms, took #{(load_elapsed * 1000).round(2)}ms"

      expect(filter_elapsed).to be < 0.01,
        "fork_sensitive_initializers should filter in <10ms, took #{(filter_elapsed * 1000).round(2)}ms"

      # Verify correct filtering behavior
      fork_sensitive = registry.fork_sensitive_initializers
      expect(fork_sensitive.size).to eq(5)
      expect(registry.initializers.size).to eq(10)
    end
  end
end
