# spec/unit/onetime/models/email_suppression_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Unit tests for Onetime::EmailSuppression — the suppression list + bounce/
# complaint event feed behind the colonel deliverability endpoints and the
# outbound guard in Onetime::Mail::Delivery::Base#deliver.
#
# These exercise the real Familia-backed structures on the test database (port
# 2121), so each example clears the model's key space to stay isolated.
RSpec.describe Onetime::EmailSuppression do
  def clear_all
    described_class.entries.clear
    described_class.index.clear
    described_class.events.clear
    described_class.sends_skipped.clear
  end

  before { clear_all }
  after  { clear_all }

  describe '.suppress!' do
    it 'stores a keyed entry and indexes it by created-at' do
      status = described_class.suppress!(
        address: 'Bounced@Example.com ',
        reason: 'bounce',
        source: 'ses',
      )

      expect(status).to eq(:created)
      entry = described_class.lookup('bounced@example.com')
      expect(entry).to include(
        'address' => 'bounced@example.com',
        'reason' => 'bounce',
        'source' => 'ses',
      )
      expect(entry['created']).to be_a(Float)
      expect(described_class.count).to eq(1)
    end

    it 'overwrites an existing entry and reports :updated' do
      described_class.suppress!(address: 'a@example.com', reason: 'bounce', source: 'ses')
      status = described_class.suppress!(address: 'a@example.com', reason: 'complaint', source: 'sendgrid')

      expect(status).to eq(:updated)
      expect(described_class.count).to eq(1)
      expect(described_class.lookup('a@example.com')['reason']).to eq('complaint')
    end

    it 'rejects unknown reasons and blank addresses' do
      expect {
        described_class.suppress!(address: 'a@example.com', reason: 'because')
      }.to raise_error(ArgumentError, /invalid suppression reason/)
      expect(described_class.suppress!(address: '  ', reason: 'manual')).to be_nil
      expect(described_class.count).to eq(0)
    end

    it 'trims the OLDEST entries past the cap (index and keyed entry together)' do
      3.times { |i| described_class.suppress!(address: "old#{i}@example.com", reason: 'manual') }

      removed = described_class.trim_suppressions!(2)

      expect(removed).to eq(1)
      expect(described_class.count).to eq(2)
      expect(described_class.suppressed?('old0@example.com')).to be(false)
      expect(described_class.lookup('old0@example.com')).to be_nil
      expect(described_class.suppressed?('old2@example.com')).to be(true)
    end
  end

  describe '.remove!' do
    it 'removes the entry and the index member' do
      described_class.suppress!(address: 'gone@example.com', reason: 'manual')

      expect(described_class.remove!('gone@example.com')).to be(true)
      expect(described_class.suppressed?('gone@example.com')).to be(false)
      expect(described_class.count).to eq(0)
    end

    it 'returns false when nothing was suppressed (no-op)' do
      expect(described_class.remove!('never@example.com')).to be(false)
    end
  end

  describe '.suppressed?' do
    it 'is an exact-address membership check, normalized' do
      described_class.suppress!(address: 'exact@example.com', reason: 'bounce')

      expect(described_class.suppressed?('EXACT@example.com')).to be(true)
      expect(described_class.suppressed?('exact@example.co')).to be(false)
      expect(described_class.suppressed?('')).to be(false)
    end
  end

  describe '.list' do
    it 'pages newest-first over the created-at index' do
      3.times do |i|
        described_class.suppress!(address: "s#{i}@example.com", reason: 'manual')
      end

      page1 = described_class.list(limit: 2, offset: 0)
      page2 = described_class.list(limit: 2, offset: 2)

      expect(page1.map { |e| e['address'] }).to eq(%w[s2@example.com s1@example.com])
      expect(page2.map { |e| e['address'] }).to eq(%w[s0@example.com])
      expect(described_class.list(limit: 0)).to eq([])
    end
  end

  describe '.skip_send? (the outbound guard)' do
    it 'skips suppressed addresses and counts the skip' do
      described_class.suppress!(address: 'bad@example.com', reason: 'bounce')

      expect(described_class.skip_send?('bad@example.com')).to be(true)
      expect(described_class.skip_send?('BAD@example.com')).to be(true)
      expect(described_class.sends_skipped.value).to eq(2)
    end

    it 'allows non-suppressed addresses without counting' do
      expect(described_class.skip_send?('fine@example.com')).to be(false)
      expect(described_class.sends_skipped.value).to eq(0)
    end

    it 'FAILS OPEN: a storage error answers false instead of raising' do
      allow(described_class).to receive(:suppressed?).and_raise(Redis::CannotConnectError, 'down')

      result = nil
      expect { result = described_class.skip_send?('bad@example.com') }.not_to raise_error
      expect(result).to be(false)
    end

    it 'still skips when only the counter write fails (best-effort tally)' do
      described_class.suppress!(address: 'bad@example.com', reason: 'bounce')
      allow(described_class).to receive(:sends_skipped).and_raise(Redis::CannotConnectError, 'down')

      expect(described_class.skip_send?('bad@example.com')).to be(true)

      # Restore the real counter before the after-hook cleanup touches Redis.
      allow(described_class).to receive(:sends_skipped).and_call_original
    end
  end

  describe '.record_event / .recent_events' do
    it 'stores events newest-first with explicit fields' do
      described_class.record_event(address: 'A@example.com', kind: 'bounce', reason: '550 user unknown', source: 'smtp-sync')
      described_class.record_event(address: 'b@example.com', kind: :complaint, source: 'ses')

      events = described_class.recent_events(10)

      expect(events.map { |e| e['kind'] }).to eq(%w[complaint bounce])
      expect(events.last).to include(
        'address' => 'a@example.com',
        'reason' => '550 user unknown',
        'source' => 'smtp-sync',
      )
      expect(events.first['reason']).to be_nil
      expect(described_class.event_count).to eq(2)
    end

    it 'supports offset paging into the newest-first ordering' do
      3.times { |i| described_class.record_event(address: "e#{i}@example.com", kind: 'bounce') }

      page2 = described_class.recent_events(2, 2)
      expect(page2.map { |e| e['address'] }).to eq(%w[e0@example.com])
    end

    it 'rejects unknown kinds (suppression is state, not an event)' do
      expect {
        described_class.record_event(address: 'a@example.com', kind: 'suppression')
      }.to raise_error(ArgumentError, /invalid event kind/)
    end

    it 'trims the feed to the cap on write (oldest dropped)' do
      3.times { |i| described_class.record_event(address: "e#{i}@example.com", kind: 'bounce') }

      described_class.trim_events!(2)

      addresses = described_class.recent_events(10).map { |e| e['address'] }
      expect(addresses).to eq(%w[e2@example.com e1@example.com])
    end
  end

  describe '.recent_event_counts' do
    it 'counts bounces and complaints inside the window only' do
      described_class.record_event(address: 'a@example.com', kind: 'bounce')
      described_class.record_event(address: 'b@example.com', kind: 'bounce')
      described_class.record_event(address: 'c@example.com', kind: 'complaint')
      # Backdate one event beyond the window by rewriting its score.
      old = described_class.record_event(address: 'old@example.com', kind: 'bounce')
      described_class.events.add(old, Familia.now - (described_class::RECENT_WINDOW + 60))

      counts = described_class.recent_event_counts

      expect(counts).to eq(bounce: 2, complaint: 1)
    end
  end
end
