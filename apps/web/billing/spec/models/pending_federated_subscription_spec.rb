# apps/web/billing/spec/models/pending_federated_subscription_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require_relative '../../models/pending_federated_subscription'

RSpec.describe Billing::PendingFederatedSubscription, type: :billing do
  let(:email_hash) { "hash_#{SecureRandom.hex(8)}" }

  describe '.record_recent_index' do
    before do
      described_class.recent_records.clear
    end

    def build_pending(hash, received_at)
      pending             = described_class.new(email_hash: hash)
      pending.received_at = received_at.to_s
      pending
    end

    it 'adds the email_hash to recent_records at the received_at score' do
      received = Time.now.to_i
      pending  = build_pending(email_hash, received)

      described_class.record_recent_index(pending)

      expect(described_class.recent_records.member?(email_hash)).to be true
      expect(described_class.recent_records.score(email_hash)).to eq(received.to_f)
    end

    it 'trims to INDEX_MAX_ENTRIES on every write' do
      stub_const('::Billing::PendingFederatedSubscription::INDEX_MAX_ENTRIES', 3)

      base_time = Time.now.to_i
      hashes    = Array.new(4) { |i| ["hash_trim_#{i}", base_time + i] }
      hashes.each { |hash, ts| described_class.record_recent_index(build_pending(hash, ts)) }

      expect(described_class.recent_records.element_count).to eq(3)

      # revrange returns newest-first; the oldest hash (lowest score) must be gone
      newest_hashes = described_class.recent_records.revrange(0, -1)
      expect(newest_hashes).to eq(%w[hash_trim_3 hash_trim_2 hash_trim_1])
      expect(described_class.recent_records.member?('hash_trim_0')).to be false
    end

    it 'swallows sorted-set write errors and warns' do
      pending = build_pending(email_hash, Time.now.to_i)

      fake_set = double('recent_records')
      allow(fake_set).to receive(:add).and_raise(RuntimeError.new('boom'))
      allow(described_class).to receive(:recent_records).and_return(fake_set)

      logger = double('billing_logger')
      allow(Onetime).to receive(:billing_logger).and_return(logger)
      expect(logger).to receive(:warn).with(
        '[PendingFederatedSubscription] recent index write failed',
        hash_including(exception: 'RuntimeError', message: 'boom', email_hash: email_hash),
      )

      expect { described_class.record_recent_index(pending) }.not_to raise_error
    end
  end

  describe '.store_from_webhook indexing' do
    before do
      described_class.recent_records.clear
    end

    it 'populates recent_records after saving the pending row' do
      subscription = build_subscription(
        'id' => 'sub_index_test',
        'status' => 'active',
        'metadata' => { 'plan_id' => 'identity_plus_v1' },
      )

      pending = described_class.store_from_webhook(
        email_hash: email_hash,
        subscription: subscription,
        region: 'EU',
        source_stripe_event_id: 'evt_index_test',
      )

      expect(pending).to be_a(described_class)
      expect(described_class.recent_records.member?(email_hash)).to be true
      expect(described_class.recent_records.score(email_hash))
        .to be_within(5).of(Time.now.to_i)
    end
  end
end
