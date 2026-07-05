# apps/api/v2/spec/models/receipt_access_timeline_spec.rb
#
# frozen_string_literal: true

require_relative '../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')

# Coverage for Receipt::Features::AccessTimeline (#3633).
#
# The timeline is the telemetry half of the lifecycle/telemetry split: reads
# append events here instead of advancing the secret's +state+ field. These
# specs pin the properties the read paths rely on:
#   * append-only recording with derived (not stored) aggregates,
#   * the retention cap that bounds memory against mechanical hammering,
#   * refusal to write next to a destroyed receipt (no orphan/resurrected key),
#   * a TTL that never outlives the receipt itself.
RSpec.describe Onetime::Receipt, type: :integration do
  before(:all) do
    require 'onetime'
    Onetime.boot! :test
  end

  let!(:pair)   { Onetime::Receipt.spawn_pair(nil, 3600, 'a secret value') }
  let(:receipt) { pair.first }
  let(:secret)  { pair.last }

  describe '#record_access_event' do
    it 'appends an event and derives count and first/last timestamps' do
      expect(receipt.access_count).to eq(0)
      expect(receipt.first_access_at).to be_nil
      expect(receipt.last_access_at).to be_nil

      t1 = Familia.now.to_f - 10
      t2 = Familia.now.to_f
      expect(receipt.record_access_event('status_get', at: t1)).to be_a(String)
      receipt.record_access_event('secret_get', at: t2)

      expect(receipt.access_count).to eq(2)
      expect(receipt.first_access_at).to be_within(0.001).of(t1)
      expect(receipt.last_access_at).to be_within(0.001).of(t2)
    end

    it 'embeds the kind in the recorded member' do
      member = receipt.record_access_event('status_get')
      expect(member).to start_with('status_get:')
    end

    it 'records nothing for a blank kind' do
      expect(receipt.record_access_event('')).to be_nil
      expect(receipt.record_access_event(nil)).to be_nil
      expect(receipt.access_count).to eq(0)
    end

    it 'does not create a timeline key next to a destroyed receipt' do
      receipt.destroy!

      expect(receipt.record_access_event('status_get')).to be_nil
      expect(receipt.access_events.exists?).to be false
    end

    it 'retains only the newest ACCESS_EVENTS_MAX events (oldest evicted)' do
      max  = Onetime::Receipt::Features::AccessTimeline::ACCESS_EVENTS_MAX
      base = Familia.now.to_f - max - 10

      (max + 5).times do |i|
        receipt.record_access_event('status_get', at: base + i)
      end

      expect(receipt.access_count).to eq(max)
      # The five oldest were trimmed: the earliest retained score is base+5.
      expect(receipt.first_access_at).to be_within(0.001).of(base + 5)
      expect(receipt.last_access_at).to be_within(0.001).of(base + max + 4)
    end

    it 'never lets the timeline outlive the receipt (TTL clamped to the receipt TTL)' do
      receipt.record_access_event('status_get')

      receipt_ttl  = receipt.current_expiration
      timeline_ttl = receipt.access_events.current_expiration

      expect(receipt_ttl).to be_positive
      expect(timeline_ttl).to be_positive
      expect(timeline_ttl).to be <= receipt_ttl
    end
  end

  describe 'lifecycle isolation' do
    it 'recording an access does not touch the receipt or secret state' do
      receipt.record_access_event('secret_get')

      expect(Onetime::Receipt.load(receipt.identifier).state).to eq('new')
      expect(Onetime::Secret.load(secret.identifier).state).to eq('new')
    end
  end

  describe '#record_receipt_view!' do
    it 'stamps receipt_viewed_at once and never advances lifecycle state' do
      expect(receipt.receipt_viewed_at.to_i).to eq(0)

      receipt.record_receipt_view!

      reloaded = Onetime::Receipt.load(receipt.identifier)
      expect(reloaded.receipt_viewed_at.to_i).to be_positive
      expect(reloaded.state).to eq('new')
      # It is telemetry, not an access of the secret link.
      expect(reloaded.access_count).to eq(0)
    end

    it 'is idempotent: repeated calls do not re-stamp receipt_viewed_at' do
      receipt.record_receipt_view!
      first_stamp = Onetime::Receipt.load(receipt.identifier).receipt_viewed_at.to_i

      receipt.record_receipt_view!
      receipt.record_receipt_view!

      expect(Onetime::Receipt.load(receipt.identifier).receipt_viewed_at.to_i).to eq(first_stamp)
    end

    it 'does not extend the receipt TTL (a page view is a safe read)' do
      before_ttl = receipt.current_expiration
      receipt.record_receipt_view!
      after_ttl = Onetime::Receipt.load(receipt.identifier).current_expiration

      expect(after_ttl).to be <= before_ttl
    end
  end

  # is_previewed is no longer a lifecycle state (#3633); it is derived from the
  # access timeline so consumers (receipt banner, dashboard status) still see
  # "the link was previewed" without a state mutation on a safe GET.
  describe 'is_previewed derived from telemetry' do
    it 'reports false before any access, while state stays new' do
      dump = receipt.safe_dump
      expect(dump[:is_previewed]).to be false
      expect(dump[:is_viewed]).to be false
      expect(receipt.state).to eq('new')
    end

    it 'reports true once the link has been accessed, without advancing state' do
      receipt.record_access_event('secret_get')

      dump = Onetime::Receipt.load(receipt.identifier).safe_dump
      expect(dump[:is_previewed]).to be true
      expect(dump[:is_viewed]).to be true
      expect(dump[:state]).to eq('new')
    end

    it 'keeps the previewed/viewed timestamps coherent with is_previewed' do
      at = Familia.now.to_f - 5
      receipt.record_access_event('secret_get', at: at)

      dump = Onetime::Receipt.load(receipt.identifier).safe_dump
      # is_previewed=true must not pair with a null previewed timestamp: the
      # timestamp falls back to the first access when the state was never set.
      expect(dump[:previewed]).to eq(at.to_i)
      expect(dump[:viewed]).to eq(at.to_i)
    end

    it 'leaves previewed/viewed null when the link has never been accessed' do
      dump = receipt.safe_dump
      expect(dump[:previewed]).to be_nil
      expect(dump[:viewed]).to be_nil
    end
  end
end
