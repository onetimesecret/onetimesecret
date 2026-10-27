# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../apps/api/v3/application'

# Creation commit boundary (docs/specs/api/01-creation-commit.md) against
# Valkey: the secret/receipt pair and its required registrations land in one
# MULTI/EXEC, failures carry persistence evidence, and optional follow-ups run
# after the commit without failing it.
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
end
