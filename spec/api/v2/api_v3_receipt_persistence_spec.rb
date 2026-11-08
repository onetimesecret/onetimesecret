# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../apps/api/v3/application'

RSpec.describe 'V2/V3 receipt persistence regressions', type: :integration do
  before(:all) { Onetime.boot! :test }

  def logic_for(klass, params, owner_id: nil)
    customer = owner_id && double('ReceiptOwner', objid: owner_id, custid: owner_id,
      extid: "ur#{owner_id}", anonymous?: false)
    strategy = double('ReceiptStrategy', user: customer, session: {}, metadata: {},
      auth_method: customer ? 'sessionauth' : 'noauth')
    klass.new(strategy, params)
  end

  def memo_logic(version, receipt, memo: 'updated memo')
    logic = logic_for(version::Logic::Secrets::UpdateReceipt,
      { 'identifier' => receipt.identifier, 'memo' => memo }, owner_id: receipt.owner_id)
    allow(logic).to receive(:require_entitlement!).and_return(true)
    logic.raise_concerns
    logic
  end

  def preview(receipt)
    logic = logic_for(V3::Logic::Secrets::ShowReceipt, { 'identifier' => receipt.identifier })
    logic.raise_concerns
    logic.process
  end

  def memo_projection(version, receipt)
    projection = { record: receipt.safe_dump }
    V3::Logic::ReceiptShape.normalize!(projection) if version == V3
    projection
  end

  def deadline(receipt)
    receipt.dbclient.call('PEXPIRETIME', receipt.dbkey)
  end

  [V2, V3].each do |version|

    describe "#{version} memo persistence" do
      it 'does not reopen a concurrently consumed creator display slot' do
        receipt, = Onetime::Receipt.spawn_pair('receipt_owner', 3600, 'generated fixture', kind: 'generate')
        updater = memo_logic(version, receipt)
        expect(preview(receipt).dig(:details, :secret_value)).to eq('generated fixture')
        marker = Onetime::Receipt.load(receipt.identifier).secret_value_shown_at
        expect(marker).to be_positive

        response = updater.process
        fresh = Onetime::Receipt.load(receipt.identifier)
        expect(fresh.secret_value_shown_at).to eq(marker)
        expect(fresh.memo).to eq('updated memo')
        expect(response).to eq(memo_projection(version, fresh))
        expect(preview(receipt).dig(:details, :secret_value)).to be_nil
      end

      it 'does not overwrite a burn committed after the memo was loaded' do
        receipt, secret = Onetime::Receipt.spawn_pair('receipt_owner', 3600, 'burn fixture')
        updater = memo_logic(version, receipt)
        expect(secret.burned!).to be(true)
        burned = Onetime::Receipt.load(receipt.identifier)

        response = updater.process
        fresh = Onetime::Receipt.load(receipt.identifier)
        expect(fresh.state).to eq('burned')
        expect(fresh.secret_identifier).to eq('')
        expect(fresh.burned).to eq(burned.burned)
        expect(fresh.memo).to eq('updated memo')
        expect(response).to eq(memo_projection(version, fresh))
        expect(Onetime::Secret.load(secret.identifier)).to be_nil
      end

      [:delete, :expire].each do |removal|
        it "does not recreate a receipt removed by #{removal} after load" do
          receipt, = Onetime::Receipt.spawn_pair('receipt_owner', 3600, 'removed fixture')
          updater = memo_logic(version, receipt)
          if removal == :delete
            receipt.dbclient.del(receipt.dbkey)
          else
            receipt.dbclient.pexpireat(receipt.dbkey, 1)
          end

          expect { updater.process }.to raise_error(Onetime::MissingSecret)
          expect(Onetime::Receipt.load(receipt.identifier)).to be_nil
          expect(receipt.dbclient.ttl(receipt.dbkey)).to eq(-2)
        end
      end

      it 'rejects deletion at the write boundary, not only a missing record at load time' do
        receipt, = Onetime::Receipt.spawn_pair('receipt_owner', 3600, 'write boundary fixture')
        updater = memo_logic(version, receipt)
        client = updater.receipt.dbclient
        allow(updater.receipt).to receive(:dbclient).and_return(client)
        writes = 0
        allow(client).to receive(:eval).and_wrap_original do |original, *args, **kwargs|
          writes += 1
          client.del(receipt.dbkey)
          original.call(*args, **kwargs)
        end

        expect { updater.process }.to raise_error(Onetime::MissingSecret)
        expect(writes).to eq(1)
        expect(Onetime::Receipt.load(receipt.identifier)).to be_nil
        expect(client.ttl(receipt.dbkey)).to eq(-2)
      end

      it 'preserves the exact existing expiry rather than applying the loaded default' do
        receipt, = Onetime::Receipt.spawn_pair('receipt_owner', 3600, 'expiry fixture')
        updater = memo_logic(version, receipt)
        receipt.dbclient.pexpire(receipt.dbkey, 30_000)
        expires_at = deadline(receipt)
        expect(expires_at).to be_positive

        updater.process
        expect(deadline(receipt)).to eq(expires_at)
        expect(Onetime::Receipt.load(receipt.identifier).memo).to eq('updated memo')
      end

      it 'supports clearing the memo while preserving the safe_dump response boundary' do
        receipt, = Onetime::Receipt.spawn_pair('receipt_owner', 3600, 'memo fixture')
        memo_logic(version, receipt).process
        updater = memo_logic(version, receipt, memo: '')
        response = updater.process
        expect(Onetime::Receipt.load(receipt.identifier).memo).to eq('')
        expect(response).to eq(memo_projection(version, updater.receipt))
        expect(response[:record]).not_to have_key(:secret_value_shown_at)
      end

      it 'retains owner authorization' do
        receipt, = Onetime::Receipt.spawn_pair('receipt_owner', 3600, 'owner fixture')
        logic = logic_for(version::Logic::Secrets::UpdateReceipt,
          { 'identifier' => receipt.identifier, 'memo' => 'unauthorized' }, owner_id: 'other_owner')
        allow(logic).to receive(:require_entitlement!).and_return(true)
        expect { logic.raise_concerns }.to raise_error(Onetime::Unauthorized)
        expect(Onetime::Receipt.load(receipt.identifier).memo).to be_nil
      end
    end
  end

  [:revealed!, :burned!, :orphaned!, :expired!].each do |transition|
    describe "atomic receipt #{transition}" do
      def prepare_transition(transition)
        receipt, = Onetime::Receipt.spawn_pair(nil, 3600, 'transition fixture', kind: 'generate')
        allow(receipt).to receive(:secret_expired?).and_return(true) if transition == :expired!
        receipt
      end

      it 'preserves fields committed by a different loaded instance and the exact expiry' do
        receipt = prepare_transition(transition)
        fresh = Onetime::Receipt.load(receipt.identifier)
        expect(fresh.claim_secret_value_display!).to be(true)
        expect(fresh.claim_once!(:receipt_viewed_at)).to be(true)
        fresh.memo = 'concurrent memo'
        fresh.save_fields(:memo, update_expiration: false)
        receipt.dbclient.pexpire(receipt.dbkey, 30_000)
        expires_at = deadline(receipt)

        expect(receipt.public_send(transition)).to be(true)
        stored = Onetime::Receipt.load(receipt.identifier)
        expect(stored.state).to eq(transition.to_s.delete_suffix('!'))
        expect(stored.secret_identifier).to eq('')
        expect(stored.secret_value_shown_at).to eq(fresh.secret_value_shown_at)
        expect(stored.receipt_viewed_at).to eq(fresh.receipt_viewed_at)
        expect(stored.memo).to eq('concurrent memo')
        expect(deadline(receipt)).to eq(expires_at)
        expect(stored.public_send(transition.to_s.delete_suffix('!'))).to be_positive if [:revealed!, :burned!].include?(transition)
      end

      it 'commits the state, lifecycle timestamp and cleared share key in the same atomic write' do
        receipt = prepare_transition(transition)
        client = receipt.dbclient
        allow(receipt).to receive(:dbclient).and_return(client)
        at_commit = nil
        allow(client).to receive(:eval).and_wrap_original do |original, *args, **kwargs|
          result = original.call(*args, **kwargs)
          at_commit = Onetime::Receipt.load(receipt.identifier)
          result
        end

        expect(receipt.public_send(transition)).to be(true)
        expect(at_commit.state).to eq(transition.to_s.delete_suffix('!'))
        expect(at_commit.secret_identifier).to eq('')
        if [:revealed!, :burned!].include?(transition)
          expect(at_commit.public_send(transition.to_s.delete_suffix('!'))).to be_positive
        end
      end

      [:before, :after].each do |boundary|
        [:delete, :expire].each do |removal|
          it "never recreates a key removed by #{removal} #{boundary} its atomic write" do
            receipt = prepare_transition(transition)
            client = receipt.dbclient
            allow(receipt).to receive(:dbclient).and_return(client)
            remove = lambda do
              removal == :delete ? client.del(receipt.dbkey) : client.pexpireat(receipt.dbkey, 1)
            end
            calls = 0
            allow(client).to receive(:eval).and_wrap_original do |original, *args, **kwargs|
              calls += 1
              remove.call if boundary == :before
              result = original.call(*args, **kwargs)
              remove.call if boundary == :after
              result
            end

            result = receipt.public_send(transition)
            expect(calls).to eq(1)
            expect(result).to be(boundary == :after ? true : nil)
            expect(Onetime::Receipt.load(receipt.identifier)).to be_nil
            expect(client.ttl(receipt.dbkey)).to eq(-2)
          end
        end
      end

      it 'does not let a stale transition replace a terminal state or duplicate its audit event' do
        receipt = prepare_transition(transition)
        winner = Onetime::Receipt.load(receipt.identifier)
        allow(receipt).to receive(:record_org_secret_activity_event)
        expect(winner.burned!).to be(true)
        before = winner.dbclient.hgetall(winner.dbkey)

        expect(receipt.public_send(transition)).to be_nil
        expect(winner.dbclient.hgetall(winner.dbkey)).to eq(before)
        expect(receipt).not_to have_received(:record_org_secret_activity_event)
      end
    end
  end

end
