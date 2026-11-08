# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../apps/api/v3/application'

# Creation commit boundary (docs/specs/api/01-creation-commit.md) against
# Valkey: the secret/receipt pair and its required registrations are written
# in one MULTI/EXEC, failures carry persistence evidence, and optional
# follow-ups run after the commit without failing it.
RSpec.describe 'API secret creation commit boundary', type: :integration do
  before(:all) { Onetime.boot! :test }

  let(:dbclient) { Familia.dbclient }
  let(:logger) { instance_spy(SemanticLogger::Logger) }
  let(:owner) { Onetime::Customer.create!(email: "creation-commit-#{SecureRandom.hex(6)}@example.com") }
  let(:org) do
    Onetime::Organization.new(
      display_name: 'Creation Commit Org',
      contact_email: "creation-commit-org-#{SecureRandom.hex(6)}@example.com",
    ).tap(&:save)
  end

  def receipt_ids(collection)
    collection.rangebyscore(0, Familia.now.to_f + 60)
  end

  def spawn_registered_pair(content = 'creation commit fixture', &block)
    block ||= lambda do |pending_receipt, _pending_secret|
      owner.add_receipt pending_receipt
      pending_receipt.add_to_organization_receipts(org)
    end
    Onetime::Receipt.spawn_pair(owner.objid, 3600, content, org_id: org.objid, &block)
  end

  describe 'a confirmed commit' do
    it 'writes the pair, both expirations and the required registrations together' do
      receipt, secret = spawn_registered_pair

      expect(dbclient.ttl(secret.dbkey)).to be_between(3500, 3600)
      expect(dbclient.ttl(receipt.dbkey)).to be_between(7100, 7200)
      expect(Onetime::Secret.instances.member?(secret)).to be(true)
      expect(Onetime::Receipt.instances.member?(receipt)).to be(true)
      expect(receipt_ids(owner.receipts)).to include(receipt.identifier)
      expect(receipt_ids(org.receipts)).to include(receipt.identifier)

      stored = Onetime::Receipt.load(receipt.identifier)
      expect(stored.org_id).to eq(org.objid)
      expect(stored.secret_identifier).to eq(secret.identifier)
      expect(Onetime::Secret.load(secret.identifier).decrypted_secret_value).to eq('creation commit fixture')
    end
  end

  describe 'a failed commit' do
    before { allow(Onetime).to receive(:secret_logger).and_return(logger) }

    it 'leaves neither the pair nor a queued registration when it fails before EXEC' do
      pending_pair = nil

      expect do
        spawn_registered_pair do |pending_receipt, pending_secret|
          owner.add_receipt pending_receipt
          pending_pair = [pending_receipt, pending_secret]
          raise IOError, 'injected failure before EXEC'
        end
      end.to raise_error(Onetime::SecretCreationFailed) { |error|
        expect([error.stage, error.persistence]).to eq([:commit, :unconfirmed])
        expect(error.cause).to be_a(IOError)
      }

      receipt, secret = pending_pair
      expect(dbclient.exists(secret.dbkey, receipt.dbkey)).to eq(0)
      expect(receipt_ids(owner.receipts)).to be_empty
    end

    it 'reports a command rejected inside EXEC as incomplete, never as success' do
      receipts_key = owner.receipts.dbkey
      dbclient.set(receipts_key, 'not a sorted set')

      expect { spawn_registered_pair }.to raise_error(Onetime::SecretCreationFailed) { |error|
        expect([error.stage, error.persistence]).to eq([:commit, :incomplete])
        expect(error.cause).to be_a(Redis::CommandError)
      }
    ensure
      dbclient.del(receipts_key)
    end

    it 'logs the evidence with shortids and never a full identifier' do
      pending_pair = nil
      failure      = nil

      expect do
        spawn_registered_pair do |pending_receipt, pending_secret|
          pending_pair = [pending_receipt, pending_secret]
          raise IOError, 'injected failure before EXEC'
        end
      end.to raise_error(Onetime::SecretCreationFailed) { |error| failure = error }

      receipt, secret = pending_pair
      expect(failure.message).to include(receipt.shortid, secret.shortid)
      expect(failure.message).not_to include(receipt.identifier, secret.identifier)
      expect(logger).to have_received(:error).with(
        'Secret creation failed',
        {
          stage: 'commit',
          persistence: 'unconfirmed',
          receipt: receipt.shortid,
          secret: secret.shortid,
          error: 'IOError',
        },
      )
    end
  end

  describe 'V3 conceal' do
    let(:payload) { { 'secret' => 'logic commit fixture', 'ttl' => '3600' } }

    def conceal_logic
      strategy = double('CreationStrategy', user: owner, session: {}, auth_method: 'sessionauth',
        metadata: { organization_context: { organization: org } })
      V3::Logic::Secrets::ConcealSecret.new(strategy, { 'secret' => payload })
    end

    it 'commits the owner and organization registrations with the pair' do
      committed = nil
      allow(Familia).to receive(:atomic_write).and_wrap_original do |original, *instances, **kwargs, &block|
        result = original.call(*instances, **kwargs, &block)
        receipt = instances.find { |instance| instance.is_a?(Onetime::Receipt) }
        committed = {
          org_id: Onetime::Receipt.load(receipt.identifier).org_id,
          owner_receipts: receipt_ids(owner.receipts),
          org_receipts: receipt_ids(org.receipts),
        }
        result
      end
      # Not swallowed by a follow-up's rescue: mock expectation errors are not
      # StandardErrors.
      expect_any_instance_of(Onetime::Receipt).not_to receive(:save)
      expect_any_instance_of(Onetime::Receipt).not_to receive(:save_fields)

      logic = conceal_logic
      logic.process

      expect(Familia).to have_received(:atomic_write).once
      expect(committed).to eq(
        org_id: org.objid,
        owner_receipts: [logic.receipt.identifier],
        org_receipts: [logic.receipt.identifier],
      )
    end

    context 'when every optional follow-up fails' do
      let(:payload) { super().merge('recipient' => 'recipient@example.com') }

      before do
        allow(Onetime).to receive(:secret_logger).and_return(logger)
        allow(owner).to receive(:increment_field).and_raise(IOError, 'injected customer stats failure')
        allow(Onetime::Customer).to receive(:secrets_created).and_raise(IOError, 'injected global stats failure')
        allow_any_instance_of(Onetime::Receipt).to receive(:record_org_secret_activity_event)
          .and_raise(IOError, 'injected audit failure')
        allow_any_instance_of(Onetime::Receipt).to receive(:deliver_by_email)
          .and_raise(IOError, 'injected email failure')
      end

      it 'returns the committed creation and logs each failure' do
        logic  = conceal_logic
        result = logic.process

        expect(result[:success]).to be(true)
        expect(result.dig(:record, :receipt, :identifier)).to eq(logic.receipt.identifier)
        expect(Onetime::Secret.load(logic.secret.identifier)).not_to be_nil
        %w[customer_stats global_stats created_activity recipient_email].each do |followup|
          expect(logger).to have_received(:error).with(
            'Secret creation follow-up failed',
            hash_including(followup: followup, persistence: 'committed', receipt: logic.receipt.shortid),
          )
        end
      end
    end
  end
end
