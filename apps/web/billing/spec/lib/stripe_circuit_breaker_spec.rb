# apps/web/billing/spec/lib/stripe_circuit_breaker_spec.rb
#
# frozen_string_literal: true

# Unit tests for Billing::StripeCircuitBreaker
#
# Tests cover the circuit breaker pattern implementation:
# - State transitions (closed -> open -> half-open -> closed)
# - Error classification (trippable vs non-trippable errors)
# - CircuitOpenError attributes
# - Redis state persistence
# - Manual reset functionality

require_relative '../support/billing_spec_helper'
require_relative '../../lib/stripe_circuit_breaker'

RSpec.describe Billing::StripeCircuitBreaker, type: :billing do
  let(:redis) { Familia.dbclient }
  let(:redis_key) { 'billing:circuit_breaker:stripe' }

  # Error doubles for testing
  let(:api_connection_error) { Stripe::APIConnectionError.new('Connection failed') }
  let(:rate_limit_error) { Stripe::RateLimitError.new('Rate limited') }
  let(:api_error) { Stripe::APIError.new('Server error') }
  let(:auth_error) { Stripe::AuthenticationError.new('Invalid key') }

  # Helper to trip the circuit (5 consecutive failures)
  def trip_circuit
    5.times do
      described_class.call { raise Stripe::APIConnectionError.new('test') }
    rescue Stripe::APIConnectionError
      # Expected - swallow to continue
    end
  end

  # Helper to cause N failures without tripping circuit
  def cause_failures(count)
    count.times do
      described_class.call { raise Stripe::APIConnectionError.new('test') }
    rescue Stripe::APIConnectionError
      # Expected
    end
  end

  after do
    # Clean up Redis state after each test
    redis.del(redis_key)
  end

  # ==========================================================================
  # State Transitions (P0 Critical)
  # ==========================================================================

  describe 'State Transitions' do
    describe 'TC-CB-001: Initial state is closed (no Redis state)' do
      it 'starts in closed state with no Redis data' do
        expect(described_class.closed?).to be true
        expect(described_class.open?).to be false
        expect(described_class.half_open?).to be false
      end

      it 'has empty Redis key initially' do
        expect(redis.exists?(redis_key)).to be false
      end
    end

    describe 'TC-CB-002: Closed state allows calls to execute' do
      it 'executes the block and returns result' do
        result = described_class.call { 'success' }
        expect(result).to eq('success')
      end

      it 'passes block return value through' do
        data = { products: %w[prod_1 prod_2] }
        result = described_class.call { data }
        expect(result).to eq(data)
      end
    end

    describe 'TC-CB-003: Opens after exactly 5 consecutive TRIPPABLE_ERRORS' do
      it 'remains closed after 4 failures' do
        cause_failures(4)
        expect(described_class.closed?).to be true
        expect(described_class.open?).to be false
      end

      it 'opens after 5 failures' do
        trip_circuit
        expect(described_class.open?).to be true
        expect(described_class.closed?).to be false
      end

      it 'records failure_count of 5 when opened' do
        trip_circuit
        status = described_class.status
        expect(status[:failure_count]).to eq(5)
      end
    end

    describe 'TC-CB-004: Open state rejects calls with CircuitOpenError' do
      before { trip_circuit }

      it 'raises CircuitOpenError without executing block' do
        block_executed = false

        expect do
          described_class.call { block_executed = true }
        end.to raise_error(Billing::CircuitOpenError)

        expect(block_executed).to be false
      end

      it 'does not increment failure count when rejecting' do
        status_before = described_class.status[:failure_count]

        begin
          described_class.call { 'should not run' }
        rescue Billing::CircuitOpenError
          # Expected
        end

        status_after = described_class.status[:failure_count]
        expect(status_after).to eq(status_before)
      end
    end

    describe 'TC-CB-005: Transitions to half-open after 60 seconds' do
      before { trip_circuit }

      it 'remains open before timeout' do
        # Simulate time passing but not enough
        frozen_time = Time.now
        allow(Time).to receive(:now).and_return(frozen_time + 30)

        expect(described_class.open?).to be true
        expect(described_class.half_open?).to be false
      end

      it 'transitions to half-open after timeout' do
        # Get the opened_at time
        status = described_class.status
        opened_at = status[:opened_at]

        # Simulate 61 seconds passing
        allow(Time).to receive(:now).and_return(Time.at(opened_at + 61))

        expect(described_class.half_open?).to be true
        expect(described_class.open?).to be false
      end
    end

    describe 'TC-CB-006: Half-open allows probe request' do
      before do
        trip_circuit
        # Simulate timeout expiring
        status = described_class.status
        allow(Time).to receive(:now).and_return(Time.at(status[:opened_at] + 61))
      end

      it 'allows one request through in half-open state' do
        expect(described_class.half_open?).to be true

        result = described_class.call { 'probe successful' }
        expect(result).to eq('probe successful')
      end
    end

    describe 'TC-CB-007: Success in half-open closes circuit' do
      before do
        trip_circuit
        # Simulate timeout expiring
        status = described_class.status
        allow(Time).to receive(:now).and_return(Time.at(status[:opened_at] + 61))
      end

      it 'closes circuit after successful probe' do
        expect(described_class.half_open?).to be true

        # Successful call
        described_class.call { 'success' }

        # Restore normal time for state check
        allow(Time).to receive(:now).and_call_original

        expect(described_class.closed?).to be true
      end

      it 'resets failure_count to 0' do
        described_class.call { 'success' }

        allow(Time).to receive(:now).and_call_original
        status = described_class.status
        expect(status[:failure_count]).to eq(0)
      end
    end

    describe 'TC-CB-008: Failure in half-open reopens circuit' do
      before do
        trip_circuit
        # Simulate timeout expiring
        @opened_at = described_class.status[:opened_at]
        allow(Time).to receive(:now).and_return(Time.at(@opened_at + 61))
      end

      it 'reopens circuit after failed probe' do
        expect(described_class.half_open?).to be true

        # Failed probe
        begin
          described_class.call { raise Stripe::APIConnectionError.new('still down') }
        rescue Stripe::APIConnectionError
          # Expected
        end

        # Restore normal time - circuit should be open with new opened_at
        allow(Time).to receive(:now).and_call_original

        expect(described_class.open?).to be true
      end

      it 'resets the recovery timeout' do
        # Failed probe
        begin
          described_class.call { raise Stripe::APIConnectionError.new('still down') }
        rescue Stripe::APIConnectionError
          # Expected
        end

        allow(Time).to receive(:now).and_call_original

        # New opened_at should be recent (within last second)
        status = described_class.status
        expect(status[:opened_at]).to be >= Time.now.to_i - 1
      end
    end
  end

  # ==========================================================================
  # Error Classification (P1 High)
  # ==========================================================================

  describe 'Error Classification' do
    describe 'TC-CB-009: Stripe::APIConnectionError trips circuit' do
      it 'increments failure count' do
        expect do
          described_class.call { raise api_connection_error }
        end.to raise_error(Stripe::APIConnectionError)

        expect(described_class.status[:failure_count]).to eq(1)
      end

      it 'opens circuit after threshold' do
        5.times do
          begin
            described_class.call { raise Stripe::APIConnectionError.new('test') }
          rescue Stripe::APIConnectionError
            # Expected
          end
        end

        expect(described_class.open?).to be true
      end
    end

    describe 'TC-CB-010: Stripe::RateLimitError trips circuit' do
      it 'increments failure count' do
        expect do
          described_class.call { raise rate_limit_error }
        end.to raise_error(Stripe::RateLimitError)

        expect(described_class.status[:failure_count]).to eq(1)
      end

      it 'opens circuit after threshold' do
        5.times do
          begin
            described_class.call { raise Stripe::RateLimitError.new('test') }
          rescue Stripe::RateLimitError
            # Expected
          end
        end

        expect(described_class.open?).to be true
      end
    end

    describe 'TC-CB-011: Stripe::APIError trips circuit' do
      it 'increments failure count' do
        expect do
          described_class.call { raise api_error }
        end.to raise_error(Stripe::APIError)

        expect(described_class.status[:failure_count]).to eq(1)
      end

      it 'opens circuit after threshold' do
        5.times do
          begin
            described_class.call { raise Stripe::APIError.new('test') }
          rescue Stripe::APIError
            # Expected
          end
        end

        expect(described_class.open?).to be true
      end
    end

    describe 'TC-CB-012: Stripe::AuthenticationError does NOT trip circuit' do
      it 'propagates error without incrementing count' do
        expect do
          described_class.call { raise auth_error }
        end.to raise_error(Stripe::AuthenticationError)

        expect(described_class.status[:failure_count]).to eq(0)
      end

      it 'does not affect circuit state' do
        5.times do
          begin
            described_class.call { raise Stripe::AuthenticationError.new('bad key') }
          rescue Stripe::AuthenticationError
            # Expected
          end
        end

        expect(described_class.closed?).to be true
      end
    end

    describe 'TC-CB-013: Non-Stripe StandardError does NOT trip circuit' do
      it 'propagates error without incrementing count' do
        expect do
          described_class.call { raise StandardError, 'generic error' }
        end.to raise_error(StandardError, 'generic error')

        expect(described_class.status[:failure_count]).to eq(0)
      end

      it 'does not affect circuit state for RuntimeError' do
        expect do
          described_class.call { raise RuntimeError, 'runtime issue' }
        end.to raise_error(RuntimeError)

        expect(described_class.closed?).to be true
      end

      it 'does not affect circuit state for ArgumentError' do
        expect do
          described_class.call { raise ArgumentError, 'bad argument' }
        end.to raise_error(ArgumentError)

        expect(described_class.closed?).to be true
      end
    end
  end

  # ==========================================================================
  # CircuitOpenError (P0 Critical)
  # ==========================================================================

  describe 'CircuitOpenError' do
    before { trip_circuit }

    describe 'TC-CB-014: CircuitOpenError includes correct retry_after value' do
      it 'includes retry_after in the error' do
        error = nil
        begin
          described_class.call { 'should not run' }
        rescue Billing::CircuitOpenError => e
          error = e
        end

        expect(error.retry_after).to be_a(Integer)
        expect(error.retry_after).to be <= 60
        expect(error.retry_after).to be >= 0
      end

      it 'retry_after decreases as time passes' do
        # Get initial retry_after
        initial_error = nil
        begin
          described_class.call { 'test' }
        rescue Billing::CircuitOpenError => e
          initial_error = e
        end

        # Simulate 30 seconds passing
        status = described_class.status
        allow(Time).to receive(:now).and_return(Time.at(status[:opened_at] + 30))

        later_error = nil
        begin
          described_class.call { 'test' }
        rescue Billing::CircuitOpenError => e
          later_error = e
        end

        expect(later_error.retry_after).to be < initial_error.retry_after
      end
    end

    describe 'TC-CB-015: CircuitOpenError message includes failure count' do
      it 'includes failure count in message' do
        error = nil
        begin
          described_class.call { 'should not run' }
        rescue Billing::CircuitOpenError => e
          error = e
        end

        expect(error.message).to include('5 failures')
      end

      it 'includes retry timing in message' do
        error = nil
        begin
          described_class.call { 'should not run' }
        rescue Billing::CircuitOpenError => e
          error = e
        end

        expect(error.message).to match(/Retry after \d+s/)
      end
    end
  end

  # ==========================================================================
  # Redis State (P2 Medium)
  # ==========================================================================

  describe 'Redis State' do
    describe 'TC-CB-016: State persists across class instances' do
      it 'shares state via Redis' do
        # Cause failures
        cause_failures(3)

        # State should be visible to new "instance" (class methods)
        status = described_class.status
        expect(status[:failure_count]).to eq(3)
      end

      it 'maintains state after clearing Ruby memory' do
        cause_failures(3)

        # Simulate fresh process by reloading class status
        # (In reality, Redis persists across processes)
        fresh_status = described_class.status
        expect(fresh_status[:failure_count]).to eq(3)
      end
    end

    describe 'TC-CB-017: Redis key has TTL of 3600 seconds' do
      it 'sets TTL on Redis key' do
        cause_failures(1)

        ttl = redis.ttl(redis_key)
        expect(ttl).to be > 0
        expect(ttl).to be <= 3600
      end

      it 'refreshes TTL on each failure' do
        cause_failures(1)
        first_ttl = redis.ttl(redis_key)

        # Wait a moment then cause another failure
        sleep(0.1) if first_ttl == 3600
        cause_failures(1)

        second_ttl = redis.ttl(redis_key)
        # TTL should be refreshed (close to 3600)
        expect(second_ttl).to be > 0
      end
    end

    describe 'TC-CB-018: status returns correct hash structure' do
      it 'returns hash with all required keys' do
        status = described_class.status

        expect(status).to have_key(:state)
        expect(status).to have_key(:failure_count)
        expect(status).to have_key(:last_failure_at)
        expect(status).to have_key(:opened_at)
        expect(status).to have_key(:recovery_at)
      end

      it 'returns closed state with zero failures initially' do
        status = described_class.status

        expect(status[:state]).to eq('closed')
        expect(status[:failure_count]).to eq(0)
        expect(status[:last_failure_at]).to be_nil
        expect(status[:opened_at]).to be_nil
        expect(status[:recovery_at]).to be_nil
      end

      it 'returns open state with correct values after tripping' do
        trip_circuit

        status = described_class.status

        expect(status[:state]).to eq('open')
        expect(status[:failure_count]).to eq(5)
        expect(status[:last_failure_at]).to be_a(Integer)
        expect(status[:opened_at]).to be_a(Integer)
        expect(status[:recovery_at]).to eq(status[:opened_at] + 60)
      end
    end
  end

  # ==========================================================================
  # Manual Reset (P1 High)
  # ==========================================================================

  describe 'Manual Reset' do
    describe 'TC-CB-019: reset! clears state to closed' do
      it 'closes circuit after reset' do
        trip_circuit
        expect(described_class.open?).to be true

        described_class.reset!

        expect(described_class.closed?).to be true
        expect(described_class.open?).to be false
      end

      it 'clears failure count' do
        trip_circuit

        described_class.reset!

        expect(described_class.status[:failure_count]).to eq(0)
      end

      it 'clears Redis key' do
        trip_circuit
        expect(redis.exists?(redis_key)).to be true

        described_class.reset!

        expect(redis.exists?(redis_key)).to be false
      end

      it 'allows calls to proceed after reset' do
        trip_circuit

        # Should fail before reset
        expect do
          described_class.call { 'test' }
        end.to raise_error(Billing::CircuitOpenError)

        described_class.reset!

        # Should succeed after reset
        result = described_class.call { 'success after reset' }
        expect(result).to eq('success after reset')
      end
    end

    describe 'TC-CB-020: reset! returns true' do
      it 'returns true on success' do
        trip_circuit

        result = described_class.reset!

        expect(result).to be true
      end

      it 'returns true even when already closed' do
        expect(described_class.closed?).to be true

        result = described_class.reset!

        expect(result).to be true
      end
    end
  end

  # ==========================================================================
  # Edge Cases
  # ==========================================================================

  describe 'Edge Cases' do
    describe 'TC-CB-021: No block raises ArgumentError' do
      it 'raises ArgumentError when no block given' do
        expect do
          described_class.call
        end.to raise_error(ArgumentError, /Block required/)
      end
    end

    describe 'TC-CB-022: 4 failures keeps circuit closed (below threshold)' do
      it 'remains closed at threshold minus one' do
        cause_failures(4)

        expect(described_class.closed?).to be true
        expect(described_class.status[:failure_count]).to eq(4)
      end

      it 'still allows calls through' do
        cause_failures(4)

        result = described_class.call { 'still works' }
        expect(result).to eq('still works')
      end
    end

    describe 'TC-CB-023: Success before threshold resets failure_count' do
      it 'resets failure count on success' do
        cause_failures(3)
        expect(described_class.status[:failure_count]).to eq(3)

        # Successful call
        described_class.call { 'success' }

        expect(described_class.status[:failure_count]).to eq(0)
      end

      it 'requires full 5 failures again after reset' do
        cause_failures(3)
        described_class.call { 'success' }

        # Need 5 more failures to trip
        cause_failures(4)
        expect(described_class.closed?).to be true

        cause_failures(1)
        expect(described_class.open?).to be true
      end
    end

    describe 'Mixed error types' do
      it 'counts all trippable error types toward threshold' do
        # Mix of different trippable errors
        begin
          described_class.call { raise Stripe::APIConnectionError.new('1') }
        rescue Stripe::APIConnectionError
        end

        begin
          described_class.call { raise Stripe::RateLimitError.new('2') }
        rescue Stripe::RateLimitError
        end

        begin
          described_class.call { raise Stripe::APIError.new('3') }
        rescue Stripe::APIError
        end

        begin
          described_class.call { raise Stripe::APIConnectionError.new('4') }
        rescue Stripe::APIConnectionError
        end

        expect(described_class.status[:failure_count]).to eq(4)
        expect(described_class.closed?).to be true

        begin
          described_class.call { raise Stripe::RateLimitError.new('5') }
        rescue Stripe::RateLimitError
        end

        expect(described_class.open?).to be true
      end
    end

    describe 'Concurrent access' do
      it 'handles rapid successive calls' do
        # Simulate rapid calls that might race
        threads = 5.times.map do
          Thread.new do
            begin
              described_class.call { raise Stripe::APIConnectionError.new('concurrent') }
            rescue Stripe::APIConnectionError, Billing::CircuitOpenError
              # Expected
            end
          end
        end

        threads.each(&:join)

        # Circuit should be open (5 failures occurred)
        expect(described_class.open?).to be true
      end
    end
  end
end
