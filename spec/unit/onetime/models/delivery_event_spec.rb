# spec/unit/onetime/models/delivery_event_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Unit tests for Onetime::DeliveryEvent — the application-side delivery
# event feed for outbound notifications (#4479). Exercises the real
# Familia-backed structures on the test database, so each example clears the
# model's key space.
#
# Run: tests/lanes/run unit --only spec/unit/onetime/models/delivery_event_spec.rb
RSpec.describe Onetime::DeliveryEvent do
  def clear_all
    described_class.events.clear
    Familia.dbclient.keys("#{described_class::COUNTS_PREFIX}:*").each { |key| Familia.dbclient.del(key) }
  end

  before { clear_all }
  after  { clear_all }

  describe '.build' do
    it 'keeps only allowlisted field shapes and omits nil fields' do
      event = described_class.build(
        channel: :email,
        stage: :queue,
        outcome: :queued,
        correlation_id: 'msg-123',
        message_id: 'queued-456',
        event_type: 'secret.viewed',
        template: :secret_viewed,
        customer_id: 'ur2a3b4c5d',
        provider: 'SES',
        provider_message_id: '0100018f-abc@email.amazonses.com',
        duration_ms: 12.7,
        attempt_count: 1,
      )

      expect(event).to include(
        'channel' => 'email',
        'stage' => 'queue',
        'outcome' => 'queued',
        'correlation_id' => 'msg-123',
        'message_id' => 'queued-456',
        'event_type' => 'secret.viewed',
        'template' => 'secret_viewed',
        'customer_id' => 'ur2a3b4c5d',
        'provider' => 'ses',
        'provider_message_id' => '0100018f-abc@email.amazonses.com',
        'duration_ms' => 12,
        'attempt_count' => 1,
      )
      expect(event['id']).to be_a(String)
      expect(event['occurred_at']).to be_a(Float)
      expect(event).not_to have_key('reason')
      expect(event).not_to have_key('http_status')
    end

    it 'rejects an outcome that does not belong to the stage' do
      expect do
        described_class.build(channel: 'email', stage: 'queue', outcome: 'sent')
      end.to raise_error(ArgumentError, /invalid outcome for stage queue/)
      expect do
        described_class.build(channel: 'email', stage: 'delivery', outcome: 'queued')
      end.to raise_error(ArgumentError, /invalid outcome for stage delivery/)
      expect do
        described_class.build(channel: 'bell', stage: 'delivery', outcome: 'sent')
      end.to raise_error(ArgumentError, /invalid channel/)
    end

    it 'drops identifiers that are not a public customer extid' do
      %w[cust:abc123 user@example.com 0123456789abcdef].each do |value|
        event = described_class.build(channel: 'email', stage: 'queue', outcome: 'queued', customer_id: value)
        expect(event).not_to have_key('customer_id')
      end
    end

    it 'stores webhook fields only for the webhook channel and email fields only for email' do
      webhook = described_class.build(
        channel: 'webhook',
        stage: 'delivery',
        outcome: 'failed',
        http_status: '503',
        target_host: 'Hooks.Example.com',
        provider: 'ses',
      )
      expect(webhook).to include('http_status' => 503, 'target_host' => 'hooks.example.com')
      expect(webhook).not_to have_key('provider')

      email = described_class.build(
        channel: 'email',
        stage: 'delivery',
        outcome: 'sent',
        http_status: 200,
        target_host: 'hooks.example.com',
        provider: 'ses',
      )
      expect(email).to include('provider' => 'ses')
      expect(email).not_to have_key('http_status')
      expect(email).not_to have_key('target_host')
    end

    it 'drops an out-of-range http status and a host that is not a host' do
      event = described_class.build(
        channel: 'webhook',
        stage: 'delivery',
        outcome: 'failed',
        http_status: 999,
        target_host: 'hooks.example.com/path?token=x',
      )
      expect(event).not_to have_key('http_status')
      expect(event).not_to have_key('target_host')
    end
  end

  describe '.scrub_message' do
    it 'replaces URIs, email addresses, credentials and long opaque runs, then bounds the length' do
      text = 'POST https://hooks.example.com/in/abc?token=s3cret for user@example.com ' \
             "failed lm_team_abcdefghij key 0123456789abcdef0123456789 #{'x' * 300}"

      scrubbed = described_class.scrub_message(text)

      expect(scrubbed).not_to include('hooks.example.com')
      expect(scrubbed).not_to include('user@example.com')
      expect(scrubbed).not_to include('lm_team_')
      expect(scrubbed).not_to include('0123456789abcdef0123456789')
      expect(scrubbed).to include('[uri]', '[email]', '[redacted]')
      expect(scrubbed.length).to be <= described_class::MAX_MESSAGE_LENGTH
    end

    it 'returns nil for nothing left' do
      expect(described_class.scrub_message(nil)).to be_nil
      expect(described_class.scrub_message("  \n ")).to be_nil
    end
  end

  describe '.record' do
    it 'stores the event newest-first and bumps the day total' do
      first  = described_class.record(channel: 'email', stage: 'queue', outcome: 'queued', correlation_id: 'a')
      second = described_class.record(channel: 'email', stage: 'delivery', outcome: 'sent', correlation_id: 'a')

      expect(described_class.count).to eq(2)
      expect(described_class.recent(10).map { |event| event['id'] }).to eq([second['id'], first['id']])

      today = described_class.daily_counts(1).last
      expect(today[:counts]).to eq('email:queue:queued' => 1, 'email:delivery:sent' => 1)
      expect(Familia.dbclient.ttl(described_class.counts_key(today[:date]))).to be > 0
    end

    it 'records the scrubbed error message and class, never the raw message' do
      error = Onetime::Mail::DeliveryError.new('SMTP delivery error: 550 <user@example.com> rejected')
      event = described_class.record(channel: 'email', stage: 'delivery', outcome: 'failed', error: error)

      expect(event['error_class']).to eq('Onetime::Mail::DeliveryError')
      expect(event['error_message']).to include('[email]')
      expect(event['error_message']).not_to include('user@example.com')
      expect(described_class.recent(1).first['error_message']).to eq(event['error_message'])
    end

    it 'returns nil instead of raising on an invalid event' do
      expect(described_class.record(channel: 'email', stage: 'queue', outcome: 'sent')).to be_nil
      expect(described_class.count).to eq(0)
    end

    it 'returns nil instead of raising when the store is unavailable' do
      store = double('events', clear: 0)
      allow(store).to receive(:add).and_raise(RedisClient::CannotConnectError, 'down')
      allow(described_class).to receive(:events).and_return(store)

      expect(described_class.record(channel: 'email', stage: 'queue', outcome: 'queued')).to be_nil
    end

    it 'trims the oldest events past the cap' do
      stub_const('Onetime::DeliveryEvent::MAX_EVENTS', 3)

      ids = (1..5).map do |n|
        described_class.record(channel: 'email', stage: 'queue', outcome: 'queued', correlation_id: "c#{n}")['id']
      end

      expect(described_class.count).to eq(3)
      expect(described_class.recent(10).map { |event| event['id'] }).to eq(ids.last(3).reverse)
    end

    it 'trims events older than the retention window' do
      old                = described_class.build(channel: 'email', stage: 'queue', outcome: 'queued')
      old['occurred_at'] = Familia.now.to_f - described_class::RETENTION - 60
      described_class.events.add(old, old['occurred_at'])

      kept = described_class.record(channel: 'email', stage: 'queue', outcome: 'queued')

      expect(described_class.recent(10).map { |event| event['id'] }).to eq([kept['id']])
    end
  end
end
