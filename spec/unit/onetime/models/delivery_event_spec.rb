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

    [
      'SMTP delivery error: 550 <user@example.com> rejected',
      'SendGrid response: {"subject":"Private launch","body":"Meet at noon"}',
      'Rejected recipient "user"@example.com',
      'Rejected recipient josé@例え.テスト',
      'Rejected recipient user@exam�ple.com',
      "Rejected recipient user@exam\xFFple.com".b,
    ].each do |message|
      it "omits upstream error text from the event and Redis: #{message.inspect}", :aggregate_failures do
        error = Onetime::Mail::DeliveryError.new(message)
        expect(error).not_to receive(:message)
        event = described_class.record(
          channel: 'email', stage: 'delivery', outcome: 'failed',
          error: error, reason: 'permanent',
        )

        expect(event).to include('error_class' => 'Onetime::Mail::DeliveryError', 'reason' => 'permanent')
        expect(event).not_to have_key('error_message')
        stored = described_class.recent(1).first
        expect(stored['id']).to eq(event['id'])
        expect(stored).not_to have_key('error_message')
        raw = Familia.dbclient.zrange(described_class.events.dbkey, 0, -1).join
        expect(raw).not_to include('error_message', 'Private launch', 'Meet at noon', 'user', 'example.com', 'josé', '例え')
        expect(described_class.daily_counts(1).last[:counts]).to eq('email:delivery:failed' => 1)
      end
    end

    it 'omits string errors and does not invoke an arbitrary message accessor' do
      error = double('upstream error')
      expect(error).not_to receive(:message)

      [error, 'Private launch: Meet at noon'].each do |value|
        event = described_class.record(channel: 'webhook', stage: 'delivery', outcome: 'failed', error: value)
        expect(event).not_to be_nil
        expect(event).not_to have_key('error_message')
        expect(event).not_to have_key('error_class')
      end
      expect(Familia.dbclient.zrange(described_class.events.dbkey, 0, -1).join).not_to include('Private launch', 'Meet at noon')
    end

    it 'returns nil instead of raising on an invalid event' do
      expect(described_class.record(channel: 'email', stage: 'queue', outcome: 'sent')).to be_nil
      expect(described_class.count).to eq(0)
    end

    it 'returns nil instead of raising when the store is unavailable' do
      store = described_class.events
      allow(store.dbclient).to receive(:eval).and_raise(RedisClient::CannotConnectError, 'down')
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

  describe '.trim!' do
    it 'returns the total removed by the cap and age limits and expires the remaining feed' do
      now = Familia.now.to_f
      allow(Familia).to receive(:now).and_return(now)
      times = [now - described_class::RETENTION - 2, now - described_class::RETENTION - 1, now - 60, now]
      seeded = times.map do |time|
        event = described_class.build(channel: 'email', stage: 'queue', outcome: 'queued')
        event['occurred_at'] = time
        described_class.events.add(event, time)
        event
      end

      expect(described_class.trim!(3)).to eq(2)
      expect(described_class.recent.map { |event| event['id'] }).to eq(seeded.last(2).reverse.map { |event| event['id'] })
      expect(Familia.dbclient.pttl(described_class.events.dbkey)).to be > 0
    end

    it 'removes the feed key when the cap is zero' do
      2.times { described_class.record(channel: 'email', stage: 'queue', outcome: 'queued') }

      expect(described_class.trim!(0)).to eq(2)
      expect(Familia.dbclient.exists?(described_class.events.dbkey)).to be(false)
    end
  end

  describe 'retention without another write' do
    it 'excludes idle aged events from recent' do
      now = Familia.now.to_f
      allow(Familia).to receive(:now).and_return(now)
      described_class.record(channel: 'email', stage: 'queue', outcome: 'queued')

      allow(Familia).to receive(:now).and_return(now + described_class::RETENTION + 1)

      expect(described_class.recent).to eq([])
      expect(Familia.dbclient.exists?(described_class.events.dbkey)).to be(false)
    end

    it 'excludes idle aged events from count' do
      now = Familia.now.to_f
      allow(Familia).to receive(:now).and_return(now)
      described_class.record(channel: 'email', stage: 'queue', outcome: 'queued')

      allow(Familia).to receive(:now).and_return(now + described_class::RETENTION + 1)

      expect(described_class.count).to eq(0)
      expect(Familia.dbclient.exists?(described_class.events.dbkey)).to be(false)
      expect(described_class.daily_counts(1).last[:counts]).to eq('email:queue:queued' => 1)
    end

    it 'excludes aged events from pages and count while newer events keep the key alive' do
      now = Familia.now.to_f
      allow(Familia).to receive(:now).and_return(now)
      described_class.record(channel: 'email', stage: 'queue', outcome: 'queued')
      allow(Familia).to receive(:now).and_return(now + 60)
      kept = described_class.record(channel: 'email', stage: 'delivery', outcome: 'sent')
      allow(Familia).to receive(:now).and_return(now + described_class::RETENTION + 1)

      expect(described_class.recent(1).map { |event| event['id'] }).to eq([kept['id']])
      expect(described_class.recent(1, 1)).to eq([])
      expect(described_class.count).to eq(1)
      expect(Familia.dbclient.zcard(described_class.events.dbkey)).to eq(1)
    end

    it 'cleans aged events when count is the first reader of an active feed' do
      now = Familia.now.to_f
      allow(Familia).to receive(:now).and_return(now)
      described_class.record(channel: 'email', stage: 'queue', outcome: 'queued')
      allow(Familia).to receive(:now).and_return(now + 60)
      kept = described_class.record(channel: 'email', stage: 'delivery', outcome: 'sent')
      allow(Familia).to receive(:now).and_return(now + described_class::RETENTION + 1)

      expect(described_class.count).to eq(1)
      expect(Familia.dbclient.zcard(described_class.events.dbkey)).to eq(1)
      expect(described_class.recent.map { |event| event['id'] }).to eq([kept['id']])
    end

    it 'sets a retention TTL on the feed key' do
      described_class.record(channel: 'email', stage: 'queue', outcome: 'queued')

      expect(Familia.dbclient.pttl(described_class.events.dbkey)).to be_between(
        (described_class::RETENTION - 1) * 1000, described_class::RETENTION * 1000 + 1,
      )
    end

    it 'does not extend the retention deadline when the feed is read or trimmed' do
      now = Familia.now.to_f
      allow(Familia).to receive(:now).and_return(now)
      described_class.record(channel: 'email', stage: 'queue', outcome: 'queued')
      key = described_class.events.dbkey
      original_ttl = Familia.dbclient.pttl(key)
      allow(Familia).to receive(:now).and_return(now + 60)

      described_class.recent
      described_class.count
      described_class.trim!

      expect(Familia.dbclient.pttl(key)).to be_between(original_ttl - 1000, original_ttl)
    end

    it 'does not shorten the newest event deadline when an older writer finishes last' do
      now = Familia.now.to_f
      allow(Familia).to receive(:now).and_return(now - 60)
      delayed = described_class.build(channel: 'email', stage: 'queue', outcome: 'queued')
      allow(Familia).to receive(:now).and_return(now)
      newest = described_class.record(channel: 'email', stage: 'delivery', outcome: 'sent')
      key = described_class.events.dbkey
      original_ttl = Familia.dbclient.pttl(key)
      allow(described_class).to receive(:build).and_return(delayed)

      expect(described_class.record(channel: 'email', stage: 'queue', outcome: 'queued')).to eq(delayed)

      expect(Familia.dbclient.pttl(key)).to be_between(original_ttl - 1000, original_ttl)
      expect(described_class.recent.map { |event| event['id'] }).to eq([newest['id'], delayed['id']])
    end

    it 'does not shorten the newest event deadline when an earlier reader resumes' do
      now = Familia.now.to_f
      allow(Familia).to receive(:now).and_return(now - 60)
      described_class.record(channel: 'email', stage: 'queue', outcome: 'queued')
      allow(Familia).to receive(:now).and_return(now)
      newest = described_class.record(channel: 'email', stage: 'delivery', outcome: 'sent')
      key = described_class.events.dbkey
      original_ttl = Familia.dbclient.pttl(key)
      allow(Familia).to receive(:now).and_return(now - 60)

      expect(described_class.recent(1).first['id']).to eq(newest['id'])
      expect(described_class.count).to eq(2)
      expect(Familia.dbclient.pttl(key)).to be_between(original_ttl - 1000, original_ttl)
    end

    it 'does not create a key when an empty feed is read or trimmed' do
      expect(described_class.recent).to eq([])
      expect(described_class.count).to eq(0)
      expect(described_class.trim!).to eq(0)
      expect(Familia.dbclient.exists?(described_class.events.dbkey)).to be(false)
    end

    it 'expires the idle Redis key without a read or another record' do
      stub_const('Onetime::DeliveryEvent::RETENTION', 1)
      described_class.record(channel: 'email', stage: 'queue', outcome: 'queued')
      key = described_class.events.dbkey

      sleep 1.1

      expect(Familia.dbclient.exists?(key)).to be(false)
      expect(described_class.recent).to eq([])
      expect(described_class.count).to eq(0)
    end
  end
end
