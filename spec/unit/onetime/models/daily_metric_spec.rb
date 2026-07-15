# spec/unit/onetime/models/daily_metric_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Unit tests for Onetime::DailyMetric — the per-day trend counters behind
# GET /api/colonel/trends (observability lane).
#
# These exercise the real Redis-backed keys on the test database (port 2121),
# so each example clears the daily_metric key space to stay isolated.
RSpec.describe Onetime::DailyMetric do
  def clear_keys
    keys = Familia.dbclient.keys("#{described_class::KEY_PREFIX}:*")
    Familia.dbclient.del(*keys) unless keys.empty?
  end

  before { clear_keys }
  after  { clear_keys }

  describe '.increment' do
    it "counts into today's UTC bucket and returns the running count" do
      expect(described_class.increment(:signups)).to eq(1)
      expect(described_class.increment(:signups)).to eq(2)

      key = described_class.key_for(:signups, Time.now.utc.to_date)
      expect(Familia.dbclient.get(key)).to eq('2')
    end

    it 'sets the ~90-day retention TTL on first increment and keeps it after' do
      described_class.increment(:signups)
      key = described_class.key_for(:signups, Time.now.utc.to_date)
      ttl = Familia.dbclient.ttl(key)
      expect(ttl).to be_between(described_class::RETENTION_TTL - 60, described_class::RETENTION_TTL)

      described_class.increment(:signups)
      expect(Familia.dbclient.ttl(key)).to be > 0
    end

    it 'buckets by UTC calendar day of the supplied time' do
      day = Time.utc(2026, 7, 1, 12, 0, 0)
      described_class.increment(:secrets_created, day)

      expect(Familia.dbclient.get('daily_metric:secrets_created:20260701')).to eq('1')
    end

    it 'is fire-and-forget: swallows dbclient errors and returns nil' do
      allow(Familia).to receive(:dbclient).and_raise(Redis::CannotConnectError, 'down')

      result = nil
      expect { result = described_class.increment(:signups) }.not_to raise_error
      expect(result).to be_nil

      # Restore the real client before the after-hook cleanup touches Redis.
      allow(Familia).to receive(:dbclient).and_call_original
    end
  end

  describe '.counts' do
    it 'returns exactly `days` zero-filled points when no data exists' do
      series = described_class.counts(:signups, 30)

      expect(series.length).to eq(30)
      expect(series.map { |point| point[:count] }).to all(eq(0))
      expect(series.last[:date]).to eq(Time.now.utc.to_date.iso8601)
    end

    it 'is ordered oldest-first, ending with today (UTC)' do
      series = described_class.counts(:signups, 7)

      dates = series.map { |point| Date.parse(point[:date]) }
      expect(dates).to eq(dates.sort)
      expect(dates.first).to eq(Time.now.utc.to_date - 6)
      expect(dates.last).to eq(Time.now.utc.to_date)
    end

    it 'reflects increments in the matching day buckets' do
      today     = Time.now.utc
      yesterday = today - 86_400
      3.times { described_class.increment(:signups, today) }
      described_class.increment(:signups, yesterday)

      series = described_class.counts(:signups, 30)

      expect(series.last).to eq(date: today.to_date.iso8601, count: 3)
      expect(series[-2]).to eq(date: yesterday.to_date.iso8601, count: 1)
      expect(series[0...-2].sum { |point| point[:count] }).to eq(0)
    end

    it 'keeps metrics namespaced from each other' do
      described_class.increment(:signups)

      expect(described_class.counts(:secrets_created, 30).sum { |p| p[:count] }).to eq(0)
    end

    it 'returns an empty array for a non-positive window' do
      expect(described_class.counts(:signups, 0)).to eq([])
    end
  end

  describe 'chokepoint instrumentation' do
    it 'Customer.create! counts one signup (fire-and-forget)' do
      expect(Onetime::DailyMetric).to receive(:increment).with(:signups)

      cust = Onetime::Customer.create!(email: "trend-#{SecureRandom.hex(4)}@example.com")
      cust.destroy!
    end

    it 'Receipt.spawn_pair counts one created secret' do
      # Identifier generation requires the HMAC secret normally set at boot
      # (configure_familia initializer); unit specs skip boot, so supply one.
      ENV['VERIFIABLE_ID_HMAC_SECRET'] ||= SecureRandom.hex(32)
      # Intercept persistence/encryption like receipt_spec.rb — the chokepoint
      # under test is the DailyMetric tick, not the Redis write pipeline.
      allow_any_instance_of(Onetime::Receipt).to receive(:save).and_return(true)
      allow_any_instance_of(Onetime::Secret).to receive(:save).and_return(true)
      allow_any_instance_of(Onetime::Secret).to receive(:ciphertext=)
      allow_any_instance_of(Onetime::Receipt)
        .to receive(:register_for_expiration_notifications).and_return(true)

      expect(Onetime::DailyMetric).to receive(:increment).with(:secrets_created)

      Onetime::Receipt.spawn_pair('anon', 3600, 'trend test secret')
    end
  end
end
