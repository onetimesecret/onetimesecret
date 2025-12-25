# spec/concurrency/fork_hooks_thread_safety_spec.rb
#
# frozen_string_literal: true

# Thread Safety Tests for Fork Hooks
#
# Usage: bundle exec rspec spec/concurrency/fork_hooks_thread_safety_spec.rb
#
# This test suite validates basic thread safety of fork hooks. While Puma's
# fork hooks are called sequentially in normal operation, these tests ensure
# the registry handles concurrent access gracefully.
#
# Coverage:
# - Concurrent read access to fork_sensitive_initializers
# - Sequential cleanup_before_fork calls maintain consistency
# - Sequential reconnect_after_fork calls maintain consistency
# - Complete fork workflow maintains correct ordering
#
# This implements Phase 4 (LOW priority) testing for GitHub issue #2205.
#
require 'spec_helper'

RSpec.describe 'Fork Hooks Thread Safety', type: :concurrency do
  # Module to track calls across test initializers
  module CallTracker
    @cleanup_calls = []
    @reconnect_calls = []
    @mutex = Mutex.new

    class << self
      attr_reader :cleanup_calls, :reconnect_calls

      def record_cleanup
        @mutex.synchronize { @cleanup_calls << Time.now.to_f }
      end

      def record_reconnect
        @mutex.synchronize { @reconnect_calls << Time.now.to_f }
      end

      def reset!
        @mutex.synchronize do
          @cleanup_calls = []
          @reconnect_calls = []
        end
      end
    end
  end

  let(:registry) { Onetime::Boot::InitializerRegistry.new }

  around do |example|
    Onetime::Boot::InitializerRegistry.with_registry(registry) { example.run }
  end

  before(:each) do
    # Reset tracking
    CallTracker.reset!
  end

  after(:each) do
    CallTracker.reset!
  end

  describe 'fork_sensitive_initializers concurrent read access' do
    it 'safely returns fork_sensitive_initializers from multiple threads' do
      # Create test initializer
      test_class = Class.new(Onetime::Boot::Initializer) do
        @phase = :fork_sensitive
        @provides = [:test_concurrent_read]

        def self.name
          'ThreadSafetyTest::ConcurrentRead'
        end

        def execute(context); end
        def cleanup; end
        def reconnect; end
      end

      # Load and run
      registry.load([test_class])
      registry.run_all

      # Read from multiple threads
      results = []
      mutex = Mutex.new

      threads = 5.times.map do
        Thread.new do
          fork_sensitive = registry.fork_sensitive_initializers
          mutex.synchronize do
            results << fork_sensitive.size
          end
        end
      end

      threads.each(&:join)

      # All threads should see 1 initializer
      expect(results).to all(eq(1))
    end
  end

  describe 'cleanup_before_fork sequential safety' do
    it 'handles multiple cleanup_before_fork calls without corruption' do
      # Create test initializer
      test_class = Class.new(Onetime::Boot::Initializer) do
        @phase = :fork_sensitive
        @provides = [:test_cleanup_safety]

        def self.name
          'ThreadSafetyTest::CleanupSafety'
        end

        def execute(context); end
        def cleanup
          CallTracker.record_cleanup
        end
        def reconnect; end
      end

      # Load and run
      registry.load([test_class])
      registry.run_all

      # Call cleanup 3 times
      3.times { registry.cleanup_before_fork }

      # Should have 3 cleanup calls
      expect(CallTracker.cleanup_calls.size).to eq(3)
    end
  end

  describe 'reconnect_after_fork sequential safety' do
    it 'handles multiple reconnect_after_fork calls without corruption' do
      # Create test initializer
      test_class = Class.new(Onetime::Boot::Initializer) do
        @phase = :fork_sensitive
        @provides = [:test_reconnect_safety]

        def self.name
          'ThreadSafetyTest::ReconnectSafety'
        end

        def execute(context); end
        def cleanup; end
        def reconnect
          CallTracker.record_reconnect
        end
      end

      # Load and run
      registry.load([test_class])
      registry.run_all

      # Call reconnect 3 times
      3.times { registry.reconnect_after_fork }

      # Should have 3 reconnect calls
      expect(CallTracker.reconnect_calls.size).to eq(3)
    end
  end

  describe 'fork workflow consistency' do
    it 'maintains correct ordering through cleanup/reconnect cycle' do
      # Create test initializer
      test_class = Class.new(Onetime::Boot::Initializer) do
        @phase = :fork_sensitive
        @provides = [:test_workflow_consistency]

        def self.name
          'ThreadSafetyTest::WorkflowConsistency'
        end

        def execute(context); end

        def cleanup
          CallTracker.record_cleanup
        end

        def reconnect
          CallTracker.record_reconnect
        end
      end

      # Load and run
      registry.load([test_class])
      registry.run_all

      # Simulate Puma fork workflow
      registry.cleanup_before_fork
      registry.reconnect_after_fork

      # Both should have been called once
      expect(CallTracker.cleanup_calls.size).to eq(1)
      expect(CallTracker.reconnect_calls.size).to eq(1)

      # Cleanup should happen before reconnect
      expect(CallTracker.cleanup_calls.first).to be < CallTracker.reconnect_calls.first
    end
  end
end
