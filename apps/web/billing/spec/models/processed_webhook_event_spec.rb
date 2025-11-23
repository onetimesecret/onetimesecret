# apps/web/billing/spec/models/processed_webhook_event_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require_relative '../../models/processed_webhook_event'

RSpec.describe Billing::ProcessedWebhookEvent, type: :billing do
  let(:event_id) { "evt_test_#{SecureRandom.hex(8)}" }
  let(:event_type) { 'customer.subscription.updated' }

  before do
    # Clear Redis before each test
    described_class.new(stripe_event_id: event_id).dbclient.del(described_class.new(stripe_event_id: event_id).dbkey)
  end

  describe 'field persistence' do
    it 'stores all Stripe event metadata' do
      event = described_class.new(stripe_event_id: event_id).load!
      event.event_type = event_type
      event.api_version = '2023-10-16'
      event.livemode = 'false'
      event.created = Time.now.to_i.to_s
      event.request_id = 'req_test123'
      event.data_object_id = 'sub_test123'
      event.pending_webhooks = '1'
      event.event_payload = '{"id":"evt_123"}'
      event.processing_status = 'pending'
      event.first_seen_at = Time.now.to_i.to_s
      event.last_attempt_at = Time.now.to_i.to_s
      event.retry_count = '0'

      # Save using the same pattern as existing methods
      event.dbclient.set(event.dbkey, event.to_json)
      event.dbclient.expire(event.dbkey, 30 * 24 * 60 * 60)

      # Reload and verify
      reloaded = described_class.new(stripe_event_id: event_id).load!
      expect(reloaded.event_type).to eq(event_type)
      expect(reloaded.api_version).to eq('2023-10-16')
      expect(reloaded.livemode).to eq('false')
      expect(reloaded.data_object_id).to eq('sub_test123')
      expect(reloaded.processing_status).to eq('pending')
      expect(reloaded.event_payload).to eq('{"id":"evt_123"}')
    end

    it 'persists processing state fields' do
      event = described_class.new(stripe_event_id: event_id).load!
      event.processing_status = 'retrying'
      event.retry_count = '2'
      event.error_message = 'Connection timeout'
      event.dbclient.set(event.dbkey, event.to_json)

      reloaded = described_class.new(stripe_event_id: event_id).load!
      expect(reloaded.processing_status).to eq('retrying')
      expect(reloaded.retry_count).to eq('2')
      expect(reloaded.error_message).to eq('Connection timeout')
    end
  end

  describe 'state checking methods' do
    describe '#success?' do
      it 'returns true when status is success' do
        event = described_class.new(stripe_event_id: event_id).load!
        event.processing_status = 'success'
        expect(event.success?).to be true
      end

      it 'returns false when status is not success' do
        event = described_class.new(stripe_event_id: event_id).load!
        event.processing_status = 'pending'
        expect(event.success?).to be false
      end
    end

    describe '#failed?' do
      it 'returns true when status is failed' do
        event = described_class.new(stripe_event_id: event_id).load!
        event.processing_status = 'failed'
        expect(event.failed?).to be true
      end

      it 'returns false when status is not failed' do
        event = described_class.new(stripe_event_id: event_id).load!
        event.processing_status = 'success'
        expect(event.failed?).to be false
      end
    end

    describe '#pending?' do
      it 'returns true when status is pending' do
        event = described_class.new(stripe_event_id: event_id).load!
        event.processing_status = 'pending'
        expect(event.pending?).to be true
      end
    end

    describe '#retrying?' do
      it 'returns true when status is retrying' do
        event = described_class.new(stripe_event_id: event_id).load!
        event.processing_status = 'retrying'
        expect(event.retrying?).to be true
      end
    end
  end

  describe 'retry logic methods' do
    describe '#retryable?' do
      it 'returns true when retry_count < 3 and not success' do
        event = described_class.new(stripe_event_id: event_id).load!
        event.processing_status = 'pending'
        event.retry_count = '2'
        expect(event.retryable?).to be true
      end

      it 'returns false when retry_count >= 3' do
        event = described_class.new(stripe_event_id: event_id).load!
        event.processing_status = 'pending'
        event.retry_count = '3'
        expect(event.retryable?).to be false
      end

      it 'returns false when status is success' do
        event = described_class.new(stripe_event_id: event_id).load!
        event.processing_status = 'success'
        event.retry_count = '1'
        expect(event.retryable?).to be false
      end
    end

    describe '#max_retries_reached?' do
      it 'returns true when retry_count >= 3' do
        event = described_class.new(stripe_event_id: event_id).load!
        event.retry_count = '3'
        expect(event.max_retries_reached?).to be true
      end

      it 'returns false when retry_count < 3' do
        event = described_class.new(stripe_event_id: event_id).load!
        event.retry_count = '2'
        expect(event.max_retries_reached?).to be false
      end
    end
  end

  describe 'state transition methods' do
    describe '#mark_processing!' do
      it 'increments retry_count' do
        event = described_class.new(stripe_event_id: event_id).load!
        event.retry_count = '1'
        event.mark_processing!

        reloaded = described_class.new(stripe_event_id: event_id).load!
        expect(reloaded.retry_count.to_i).to eq(2)
      end

      it 'sets status to pending' do
        event = described_class.new(stripe_event_id: event_id).load!
        event.mark_processing!

        reloaded = described_class.new(stripe_event_id: event_id).load!
        expect(reloaded.processing_status).to eq('pending')
      end

      it 'updates last_attempt_at' do
        event = described_class.new(stripe_event_id: event_id).load!
        before = Time.now.to_i
        event.mark_processing!

        reloaded = described_class.new(stripe_event_id: event_id).load!
        expect(reloaded.last_attempt_at.to_i).to be >= before
      end
    end

    describe '#mark_success!' do
      it 'sets status to success' do
        event = described_class.new(stripe_event_id: event_id).load!
        event.processing_status = 'pending'
        event.mark_success!

        reloaded = described_class.new(stripe_event_id: event_id).load!
        expect(reloaded.processing_status).to eq('success')
      end

      it 'clears error_message' do
        event = described_class.new(stripe_event_id: event_id).load!
        event.error_message = 'Previous error'
        event.mark_success!

        reloaded = described_class.new(stripe_event_id: event_id).load!
        expect(reloaded.error_message).to be_nil
      end

      it 'updates processed_at' do
        event = described_class.new(stripe_event_id: event_id).load!
        before = Time.now.to_i
        event.mark_success!

        reloaded = described_class.new(stripe_event_id: event_id).load!
        expect(reloaded.processed_at.to_i).to be >= before
      end
    end

    describe '#mark_failed!' do
      it 'sets status to retrying when retries remain' do
        event = described_class.new(stripe_event_id: event_id).load!
        event.retry_count = '1'
        error = StandardError.new('Test error')
        event.mark_failed!(error)

        reloaded = described_class.new(stripe_event_id: event_id).load!
        expect(reloaded.processing_status).to eq('retrying')
      end

      it 'sets status to failed when max retries reached' do
        event = described_class.new(stripe_event_id: event_id).load!
        event.retry_count = '3'
        error = StandardError.new('Test error')
        event.mark_failed!(error)

        reloaded = described_class.new(stripe_event_id: event_id).load!
        expect(reloaded.processing_status).to eq('failed')
      end

      it 'stores error message' do
        event = described_class.new(stripe_event_id: event_id).load!
        event.retry_count = '1'
        error = StandardError.new('Connection timeout')
        event.mark_failed!(error)

        reloaded = described_class.new(stripe_event_id: event_id).load!
        expect(reloaded.error_message).to eq('Connection timeout')
      end
    end
  end

  describe 'debugging methods' do
    describe '#deserialize_payload' do
      it 'returns parsed JSON' do
        event = described_class.new(stripe_event_id: event_id).load!
        event.event_payload = '{"id":"evt_123","type":"test.event"}'
        payload = event.deserialize_payload
        expect(payload['id']).to eq('evt_123')
        expect(payload['type']).to eq('test.event')
      end

      it 'returns nil for invalid JSON' do
        event = described_class.new(stripe_event_id: event_id).load!
        event.event_payload = 'invalid json'
        expect(event.deserialize_payload).to be_nil
      end

      it 'returns nil when payload is missing' do
        event = described_class.new(stripe_event_id: event_id).load!
        expect(event.deserialize_payload).to be_nil
      end
    end

    describe '#stripe_event' do
      it 'reconstructs Stripe event from payload' do
        event = described_class.new(stripe_event_id: event_id).load!
        event.event_payload = {
          id: 'evt_123',
          object: 'event',
          type: 'customer.subscription.updated',
          data: { object: { id: 'sub_123' } }
        }.to_json

        stripe_event = event.stripe_event
        expect(stripe_event).to be_a(Stripe::Event)
        expect(stripe_event.id).to eq('evt_123')
        expect(stripe_event.type).to eq('customer.subscription.updated')
      end

      it 'returns nil when payload is missing' do
        event = described_class.new(stripe_event_id: event_id).load!
        expect(event.stripe_event).to be_nil
      end
    end
  end

  describe 'legacy compatibility' do
    describe '.mark_processed!' do
      it 'still works and sets status to success' do
        event = described_class.mark_processed!(event_id, event_type)
        reloaded = described_class.new(stripe_event_id: event_id).load!
        expect(reloaded.event_type).to eq(event_type)
        expect(reloaded.processing_status).to eq('success')
        expect(reloaded.processed_at).not_to be_nil
      end
    end

    describe '.mark_processed_if_new!' do
      it 'returns true for new event' do
        result = described_class.mark_processed_if_new!(event_id, event_type)
        expect(result).to be true
      end

      it 'returns false for existing event' do
        described_class.mark_processed_if_new!(event_id, event_type)
        result = described_class.mark_processed_if_new!(event_id, event_type)
        expect(result).to be false
      end

      it 'sets processing_status to success' do
        described_class.mark_processed_if_new!(event_id, event_type)
        reloaded = described_class.new(stripe_event_id: event_id).load!
        expect(reloaded.processing_status).to eq('success')
      end
    end

    describe '.processed?' do
      it 'works with enhanced events' do
        described_class.mark_processed_if_new!(event_id, event_type)
        expect(described_class.processed?(event_id)).to be true
      end
    end
  end

  describe 'TTL configuration' do
    it 'has default expiration of 30 days' do
      event = described_class.new(stripe_event_id: event_id).load!
      expect(event.default_expiration).to eq(30 * 24 * 60 * 60)
    end
  end

  describe 'state machine flows' do
    it 'transitions pending → success' do
      event = described_class.new(stripe_event_id: event_id).load!
      event.first_seen_at = Time.now.to_i.to_s
      event.mark_processing!
      event.mark_success!

      reloaded = described_class.new(stripe_event_id: event_id).load!
      expect(reloaded.processing_status).to eq('success')
      expect(reloaded.retry_count.to_i).to eq(1)
      expect(reloaded.processed_at).not_to be_nil
    end

    it 'transitions pending → retrying → success' do
      event = described_class.new(stripe_event_id: event_id).load!
      event.first_seen_at = Time.now.to_i.to_s
      event.mark_processing!
      error = StandardError.new('Temporary error')
      event.mark_failed!(error)

      reloaded = described_class.new(stripe_event_id: event_id).load!
      expect(reloaded.processing_status).to eq('retrying')

      reloaded.mark_processing!
      reloaded.mark_success!

      final = described_class.new(stripe_event_id: event_id).load!
      expect(final.processing_status).to eq('success')
      expect(final.retry_count.to_i).to eq(2)
      expect(final.error_message).to be_nil
    end

    it 'transitions to failed after 3 attempts' do
      event = described_class.new(stripe_event_id: event_id).load!
      event.first_seen_at = Time.now.to_i.to_s

      # Attempt 1
      event.mark_processing!
      event.mark_failed!(StandardError.new('Error 1'))

      # Attempt 2
      event = described_class.new(stripe_event_id: event_id).load!
      event.mark_processing!
      event.mark_failed!(StandardError.new('Error 2'))

      # Attempt 3
      event = described_class.new(stripe_event_id: event_id).load!
      event.mark_processing!
      event.mark_failed!(StandardError.new('Error 3'))

      final = described_class.new(stripe_event_id: event_id).load!
      expect(final.processing_status).to eq('failed')
      expect(final.retry_count.to_i).to eq(3)
      expect(final.max_retries_reached?).to be true
    end
  end
end
