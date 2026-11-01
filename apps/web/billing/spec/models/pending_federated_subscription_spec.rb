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

  # #4754 review F1/F2: sync order, conditional retirement, per-hash lock.
  describe 'sync order' do
    after do
      described_class.find_by_email_hash(email_hash)&.destroy!
    end

    def store(event_id)
      described_class.store_from_webhook(
        email_hash: email_hash,
        subscription: build_subscription(
          'id' => 'sub_sync_order',
          'status' => 'active',
          'metadata' => { 'plan_id' => 'identity_plus_v1' },
        ),
        region: 'EU',
        source_stripe_event_id: event_id,
      )
    end

    def org_double(version: nil, synced_at: nil)
      instance_double(Onetime::Organization, subscription_sync_version: version, subscription_synced_at: synced_at)
    end

    it 'stamps each stored record with a higher sync_version, within one second' do
      Timecop.freeze(Time.at(1_893_456_000)) do
        first  = store('evt_first')
        second = store('evt_second')
        expect(second.received_at).to eq(first.received_at)
        expect(second.sync_version.to_i).to be > first.sync_version.to_i
        expect(described_class.find_by_email_hash(email_hash).sync_version.to_i).to eq(second.sync_version.to_i)
      end
    end

    describe '#superseded_by?' do
      it 'compares versions when both sides have one, ignoring a tied timestamp' do
        pending              = described_class.new(email_hash)
        pending.received_at  = '1000'
        pending.sync_version = 10
        version              = 10
        now                  = 1000

        expect(pending.superseded_by?(org_double(version: version, synced_at: now))).to be(true)
        expect(pending.superseded_by?(org_double(version: version + 1, synced_at: now))).to be(true)
        expect(pending.superseded_by?(org_double(version: version - 1, synced_at: now))).to be(false)
      end

      it 'falls back to the timestamps for a record or an org without a version' do
        legacy             = described_class.new(email_hash)
        legacy.received_at = '1000'

        expect(legacy.superseded_by?(org_double)).to be(false)
        expect(legacy.superseded_by?(org_double(synced_at: 1000))).to be(true)
        expect(legacy.superseded_by?(org_double(version: 5, synced_at: 999))).to be(false)

        versioned = store('evt_after_legacy_sync')
        expect(versioned.superseded_by?(org_double(synced_at: versioned.received_at.to_i - 1))).to be(false)
      end
    end

    describe '#destroy_if_unchanged!' do
      it 'destroys the stored copy it was loaded from' do
        store('evt_once')
        loaded = described_class.find_by_email_hash(email_hash)

        expect(loaded.destroy_if_unchanged!).to be(true)
        expect(described_class.find_by_email_hash(email_hash)).to be_nil
      end

      it 'keeps a newer snapshot stored for the hash after it was loaded' do
        store('evt_old')
        loaded = described_class.find_by_email_hash(email_hash)
        store('evt_new')

        expect(loaded.destroy_if_unchanged!).to be(false)
        expect(described_class.find_by_email_hash(email_hash).source_stripe_event_id).to eq('evt_new')
      end
    end

    describe '#retire_for!' do
      let(:synced_org) { instance_double(Onetime::Organization, objid: 'org_synced') }
      let(:waiting_org) { instance_double(Onetime::Organization, objid: 'org_waiting') }

      before do
        allow(Onetime::Organization).to receive(:find_federated_by_email_hash)
          .with(email_hash).and_return([synced_org, waiting_org])
        allow(described_class).to receive(:awaiting_mailbox_proof?).with(synced_org).and_return(false)
      end

      it 'destroys the record when no other workspace for the hash is waiting on it' do
        allow(described_class).to receive(:awaiting_mailbox_proof?).with(waiting_org).and_return(false)
        loaded = store('evt_retire')

        expect(loaded.retire_for!(synced_org)).to be(true)
        expect(described_class.find_by_email_hash(email_hash)).to be_nil
      end

      it 'keeps the record while another workspace for the hash waits for mailbox proof' do
        allow(described_class).to receive(:awaiting_mailbox_proof?).with(waiting_org).and_return(true)
        loaded = store('evt_keep')

        expect(loaded.retire_for!(synced_org)).to be(false)
        expect(described_class.find_by_email_hash(email_hash).source_stripe_event_id).to eq('evt_keep')
      end

      it 'does not count the workspace it retires for as waiting' do
        allow(described_class).to receive(:awaiting_mailbox_proof?).with(synced_org).and_return(true)
        allow(described_class).to receive(:awaiting_mailbox_proof?).with(waiting_org).and_return(false)
        loaded = store('evt_self')

        expect(loaded.retire_for!(synced_org)).to be(true)
      end

      it 'destroys the record regardless when keep_for_deferred is false' do
        allow(described_class).to receive(:awaiting_mailbox_proof?).with(waiting_org).and_return(true)
        loaded = store('evt_cancel')

        expect(loaded.retire_for!(synced_org, keep_for_deferred: false)).to be(true)
        expect(described_class.find_by_email_hash(email_hash)).to be_nil
      end
    end
  end

  describe '.with_federation_lock' do
    let(:lock) { Familia::Lock.new(described_class.federation_lock_key(email_hash)) }

    after { lock.force_unlock! }

    it 'keeps the lock for the block and releases it after' do
      held = described_class.with_federation_lock(email_hash, wait: 0.1) { lock.locked? }
      expect(held).to be(true)
      expect(lock.locked?).to be(false)
    end

    it 'releases the lock when the block raises' do
      expect do
        described_class.with_federation_lock(email_hash, wait: 0.1) { raise ArgumentError, 'boom' }
      end.to raise_error(ArgumentError)
      expect(lock.locked?).to be(false)
    end

    it 'raises FederationLockTimeout without running the block while another holder keeps it' do
      token = lock.acquire(ttl: 30)
      ran   = false

      expect do
        described_class.with_federation_lock(email_hash, wait: 0.1) { ran = true }
      end.to raise_error(described_class::FederationLockTimeout)
      expect(ran).to be(false)
      expect(lock.held_by?(token)).to be(true)
    end
  end
end
