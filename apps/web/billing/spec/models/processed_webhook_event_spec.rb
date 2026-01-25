# apps/web/billing/spec/models/processed_webhook_event_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require_relative '../../models/stripe_webhook_event'

RSpec.describe Billing::StripeWebhookEvent, type: :billing do
  let(:event_id) { "evt_test_#{SecureRandom.hex(8)}" }
  let(:event_type) { 'customer.subscription.updated' }

  before do
    # Clear Redis before each test
    described_class.new(stripe_event_id: event_id).dbclient.del(described_class.new(stripe_event_id: event_id).dbkey)
  end

  describe 'field persistence' do
    it 'stores all Stripe event metadata' do
      event                   = described_class.new(stripe_event_id: event_id)
      event.event_type        = event_type
      event.api_version       = '2023-10-16'
      event.livemode          = 'false'
      event.created           = Time.now.to_i.to_s
      event.request_id        = 'req_test123'
      event.data_object_id    = 'sub_test123'
      event.pending_webhooks  = '1'
      event.event_payload     = '{"id":"evt_123"}'
      event.processing_status = 'pending'
      event.first_seen_at     = Time.now.to_i.to_s
      event.last_attempt_at   = Time.now.to_i.to_s
      event.attempt_count       = '0'
      event.save

      # Reload and verify
      reloaded = described_class.find_by_identifier(event_id)
      expect(reloaded.event_type).to eq(event_type)
      expect(reloaded.api_version).to eq('2023-10-16')
      expect(reloaded.livemode).to eq('false')
      expect(reloaded.data_object_id).to eq('sub_test123')
      expect(reloaded.processing_status).to eq('pending')
      expect(reloaded.event_payload).to eq('{"id":"evt_123"}')
    end

    it 'persists processing state fields' do
      event                   = described_class.new(stripe_event_id: event_id)
      event.processing_status = 'retrying'
      event.attempt_count       = '2'
      event.error_message     = 'Connection timeout'
      event.save

      reloaded = described_class.find_by_identifier(event_id)
      expect(reloaded.processing_status).to eq('retrying')
      expect(reloaded.attempt_count).to eq('2')
      expect(reloaded.error_message).to eq('Connection timeout')
    end
  end

  describe 'state checking methods' do
    describe '#success?' do
      it 'returns true when status is success' do
        event                   = described_class.new(stripe_event_id: event_id)
        event.processing_status = 'success'
        expect(event.success?).to be true
      end

      it 'returns false when status is not success' do
        event                   = described_class.new(stripe_event_id: event_id)
        event.processing_status = 'pending'
        expect(event.success?).to be false
      end
    end

    describe '#failed?' do
      it 'returns true when status is failed' do
        event                   = described_class.new(stripe_event_id: event_id)
        event.processing_status = 'failed'
        expect(event.failed?).to be true
      end

      it 'returns false when status is not failed' do
        event                   = described_class.new(stripe_event_id: event_id)
        event.processing_status = 'success'
        expect(event.failed?).to be false
      end
    end

    describe '#pending?' do
      it 'returns true when status is pending' do
        event                   = described_class.new(stripe_event_id: event_id)
        event.processing_status = 'pending'
        expect(event.pending?).to be true
      end
    end

    describe '#retrying?' do
      it 'returns true when status is retrying' do
        event                   = described_class.new(stripe_event_id: event_id)
        event.processing_status = 'retrying'
        expect(event.retrying?).to be true
      end
    end
  end

  describe 'retry logic methods' do
    describe '#retryable?' do
      it 'returns true when attempt_count < 3 and not success' do
        event                   = described_class.new(stripe_event_id: event_id)
        event.processing_status = 'pending'
        event.attempt_count       = '2'
        expect(event.retryable?).to be true
      end

      it 'returns false when attempt_count >= 3' do
        event                   = described_class.new(stripe_event_id: event_id)
        event.processing_status = 'pending'
        event.attempt_count       = '3'
        expect(event.retryable?).to be false
      end

      it 'returns false when status is success' do
        event                   = described_class.new(stripe_event_id: event_id)
        event.processing_status = 'success'
        event.attempt_count       = '1'
        expect(event.retryable?).to be false
      end
    end

    describe '#max_attempts_reached?' do
      it 'returns true when attempt_count >= 3' do
        event             = described_class.new(stripe_event_id: event_id)
        event.attempt_count = '3'
        expect(event.max_attempts_reached?).to be true
      end

      it 'returns false when attempt_count < 3' do
        event             = described_class.new(stripe_event_id: event_id)
        event.attempt_count = '2'
        expect(event.max_attempts_reached?).to be false
      end
    end
  end

  describe 'state transition methods' do
    describe '#mark_processing!' do
      it 'increments attempt_count' do
        event             = described_class.new(stripe_event_id: event_id)
        event.attempt_count = '1'
        event.mark_processing!

        reloaded = described_class.find_by_identifier(event_id)
        expect(reloaded.attempt_count.to_i).to eq(2)
      end

      it 'sets status to pending' do
        event = described_class.new(stripe_event_id: event_id)
        event.mark_processing!

        reloaded = described_class.find_by_identifier(event_id)
        expect(reloaded.processing_status).to eq('pending')
      end

      it 'updates last_attempt_at' do
        event  = described_class.new(stripe_event_id: event_id)
        before = Time.now.to_i
        event.mark_processing!

        reloaded = described_class.find_by_identifier(event_id)
        expect(reloaded.last_attempt_at.to_i).to be >= before
      end
    end

    describe '#mark_success!' do
      it 'sets status to success' do
        event                   = described_class.new(stripe_event_id: event_id)
        event.processing_status = 'pending'
        event.mark_success!

        reloaded = described_class.find_by_identifier(event_id)
        expect(reloaded.processing_status).to eq('success')
      end

      it 'clears error_message' do
        event               = described_class.new(stripe_event_id: event_id)
        event.error_message = 'Previous error'
        event.mark_success!

        reloaded = described_class.find_by_identifier(event_id)
        expect(reloaded.error_message).to be_nil
      end

      it 'updates processed_at' do
        event  = described_class.new(stripe_event_id: event_id)
        before = Time.now.to_i
        event.mark_success!

        reloaded = described_class.find_by_identifier(event_id)
        expect(reloaded.processed_at.to_i).to be >= before
      end
    end

    describe '#mark_failed!' do
      it 'sets status to retrying when retries remain' do
        event             = described_class.new(stripe_event_id: event_id)
        event.attempt_count = '1'
        error             = StandardError.new('Test error')
        event.mark_failed!(error)

        reloaded = described_class.find_by_identifier(event_id)
        expect(reloaded.processing_status).to eq('retrying')
      end

      it 'sets status to failed when max retries reached' do
        event             = described_class.new(stripe_event_id: event_id)
        event.attempt_count = '3'
        error             = StandardError.new('Test error')
        event.mark_failed!(error)

        reloaded = described_class.find_by_identifier(event_id)
        expect(reloaded.processing_status).to eq('failed')
      end

      it 'stores error message' do
        event             = described_class.new(stripe_event_id: event_id)
        event.attempt_count = '1'
        error             = StandardError.new('Connection timeout')
        event.mark_failed!(error)

        reloaded = described_class.find_by_identifier(event_id)
        expect(reloaded.error_message).to eq('Connection timeout')
      end
    end
  end

  describe 'debugging methods' do
    describe '#deserialize_payload' do
      it 'returns parsed JSON' do
        event               = described_class.new(stripe_event_id: event_id)
        event.event_payload = '{"id":"evt_123","type":"test.event"}'
        payload             = event.deserialize_payload
        expect(payload['id']).to eq('evt_123')
        expect(payload['type']).to eq('test.event')
      end

      it 'returns nil for invalid JSON' do
        event               = described_class.new(stripe_event_id: event_id)
        event.event_payload = 'invalid json'
        expect(event.deserialize_payload).to be_nil
      end

      it 'returns nil when payload is missing' do
        event = described_class.new(stripe_event_id: event_id)
        expect(event.deserialize_payload).to be_nil
      end
    end

    describe '#stripe_event' do
      it 'reconstructs Stripe event from payload' do
        event               = described_class.new(stripe_event_id: event_id)
        event.event_payload = {
          id: 'evt_123',
          object: 'event',
          type: 'customer.subscription.updated',
          data: { object: { id: 'sub_123' } },
        }.to_json

        stripe_event = event.stripe_event
        expect(stripe_event).to be_a(Stripe::Event)
        expect(stripe_event.id).to eq('evt_123')
        expect(stripe_event.type).to eq('customer.subscription.updated')
      end

      it 'returns nil when payload is missing' do
        event = described_class.new(stripe_event_id: event_id)
        expect(event.stripe_event).to be_nil
      end
    end
  end

  describe 'TTL configuration' do
    it 'has default expiration of 5 days' do
      event = described_class.new(stripe_event_id: event_id)
      # 5 days covers Stripe retry window + debugging
      expect(event.default_expiration).to eq(5 * 24 * 60 * 60)
    end
  end

  describe 'state machine flows' do
    it 'transitions pending → success' do
      event               = described_class.new(stripe_event_id: event_id)
      event.first_seen_at = Time.now.to_i.to_s
      event.mark_processing!
      event.mark_success!

      reloaded = described_class.find_by_identifier(event_id)
      expect(reloaded.processing_status).to eq('success')
      expect(reloaded.attempt_count.to_i).to eq(1)
      expect(reloaded.processed_at).not_to be_nil
    end

    it 'transitions pending → retrying → success' do
      event               = described_class.new(stripe_event_id: event_id)
      event.first_seen_at = Time.now.to_i.to_s
      event.mark_processing!
      error               = StandardError.new('Temporary error')
      event.mark_failed!(error)

      reloaded = described_class.find_by_identifier(event_id)
      expect(reloaded.processing_status).to eq('retrying')

      reloaded.mark_processing!
      reloaded.mark_success!

      final = described_class.find_by_identifier(event_id)
      expect(final.processing_status).to eq('success')
      expect(final.attempt_count.to_i).to eq(2)
      expect(final.error_message).to be_nil
    end

    it 'transitions to failed after 3 attempts' do
      event               = described_class.new(stripe_event_id: event_id)
      event.first_seen_at = Time.now.to_i.to_s
      event.save

      # Attempt 1
      event.mark_processing!
      event.mark_failed!(StandardError.new('Error 1'))

      # Attempt 2 - reload from Redis to get updated attempt_count
      event = described_class.find_by_identifier(event_id)
      event.mark_processing!
      event.mark_failed!(StandardError.new('Error 2'))

      # Attempt 3 - reload from Redis to get updated attempt_count
      event = described_class.find_by_identifier(event_id)
      event.mark_processing!
      event.mark_failed!(StandardError.new('Error 3'))

      final = described_class.find_by_identifier(event_id)
      expect(final.processing_status).to eq('failed')
      expect(final.attempt_count.to_i).to eq(3)
      expect(final.max_attempts_reached?).to be true
    end
  end

  describe 'circuit breaker retry methods' do
    describe '#circuit_retry_scheduled?' do
      it 'returns true when circuit_retry_at is set' do
        event = described_class.new(stripe_event_id: event_id)
        event.circuit_retry_at = (Time.now.to_i + 60).to_s
        expect(event.circuit_retry_scheduled?).to be true
      end

      it 'returns false when circuit_retry_at is nil' do
        event = described_class.new(stripe_event_id: event_id)
        expect(event.circuit_retry_scheduled?).to be false
      end

      it 'returns false when circuit_retry_at is 0' do
        event = described_class.new(stripe_event_id: event_id)
        event.circuit_retry_at = '0'
        expect(event.circuit_retry_scheduled?).to be false
      end
    end

    describe '#circuit_retry_due?' do
      it 'returns true when retry time has passed' do
        event = described_class.new(stripe_event_id: event_id)
        event.circuit_retry_at = (Time.now.to_i - 10).to_s
        event.circuit_retry_count = '1'
        expect(event.circuit_retry_due?).to be true
      end

      it 'returns false when retry time is in the future' do
        event = described_class.new(stripe_event_id: event_id)
        event.circuit_retry_at = (Time.now.to_i + 60).to_s
        event.circuit_retry_count = '1'
        expect(event.circuit_retry_due?).to be false
      end

      it 'returns false when max retries reached' do
        event = described_class.new(stripe_event_id: event_id)
        event.circuit_retry_at = (Time.now.to_i - 10).to_s
        event.circuit_retry_count = '5'
        expect(event.circuit_retry_due?).to be false
      end

      it 'returns false when not scheduled' do
        event = described_class.new(stripe_event_id: event_id)
        expect(event.circuit_retry_due?).to be false
      end
    end

    describe '#circuit_retry_exhausted?' do
      it 'returns true when circuit_retry_count >= 5' do
        event = described_class.new(stripe_event_id: event_id)
        event.circuit_retry_count = '5'
        expect(event.circuit_retry_exhausted?).to be true
      end

      it 'returns false when circuit_retry_count < 5' do
        event = described_class.new(stripe_event_id: event_id)
        event.circuit_retry_count = '4'
        expect(event.circuit_retry_exhausted?).to be false
      end

      it 'returns false when circuit_retry_count is nil' do
        event = described_class.new(stripe_event_id: event_id)
        expect(event.circuit_retry_exhausted?).to be false
      end
    end

    describe '#schedule_circuit_retry' do
      it 'sets circuit_retry_at to future timestamp' do
        event = described_class.new(stripe_event_id: event_id)
        before = Time.now.to_i
        event.schedule_circuit_retry(delay_seconds: 120)

        expect(event.circuit_retry_at.to_i).to be >= before + 120
        expect(event.circuit_retry_at.to_i).to be <= before + 125
      end

      it 'increments circuit_retry_count' do
        event = described_class.new(stripe_event_id: event_id)
        event.circuit_retry_count = '1'
        event.schedule_circuit_retry(delay_seconds: 60)

        expect(event.circuit_retry_count).to eq('2')
      end

      it 'sets processing_status to retrying' do
        event = described_class.new(stripe_event_id: event_id)
        event.schedule_circuit_retry(delay_seconds: 60)

        expect(event.processing_status).to eq('retrying')
      end

      it 'uses exponential backoff when delay not specified' do
        event = described_class.new(stripe_event_id: event_id)
        event.circuit_retry_count = '2' # Third retry = 60 * 2^2 = 240s
        before = Time.now.to_i
        event.schedule_circuit_retry

        # Should be around 240 seconds (60 * 4)
        expected_delay = 60 * (2**2)
        expect(event.circuit_retry_at.to_i).to be >= before + expected_delay - 5
        expect(event.circuit_retry_at.to_i).to be <= before + expected_delay + 5
      end

      it 'persists changes to Redis' do
        event = described_class.new(stripe_event_id: event_id)
        event.schedule_circuit_retry(delay_seconds: 60)

        reloaded = described_class.find_by_identifier(event_id)
        expect(reloaded.circuit_retry_at).not_to be_nil
        expect(reloaded.circuit_retry_count).to eq('1')
      end
    end

    describe '#clear_circuit_retry' do
      it 'clears circuit_retry_at' do
        event = described_class.new(stripe_event_id: event_id)
        event.circuit_retry_at = (Time.now.to_i + 60).to_s
        event.circuit_retry_count = '2'
        event.save

        event.clear_circuit_retry

        reloaded = described_class.find_by_identifier(event_id)
        expect(reloaded.circuit_retry_at).to be_nil
        expect(reloaded.circuit_retry_count).to eq('0')
      end
    end
  end

  describe 'circuit retry flow' do
    it 'schedules retry → processes on circuit recovery' do
      event = described_class.new(stripe_event_id: event_id)
      event.first_seen_at = Time.now.to_i.to_s
      event.save

      # Initial processing fails due to circuit open
      # Use 0 delay to avoid timing issues in tests
      event.schedule_circuit_retry(delay_seconds: 0)

      reloaded = described_class.find_by_identifier(event_id)
      expect(reloaded.circuit_retry_scheduled?).to be true
      expect(reloaded.circuit_retry_count).to eq('1')
      expect(reloaded.processing_status).to eq('retrying')

      # With 0 delay, should be immediately due
      expect(reloaded.circuit_retry_due?).to be true

      # Successful retry
      reloaded.clear_circuit_retry
      reloaded.mark_success!

      final = described_class.find_by_identifier(event_id)
      expect(final.processing_status).to eq('success')
      expect(final.circuit_retry_at).to be_nil
    end
  end
end
