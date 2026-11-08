# frozen_string_literal: true

require 'spec_helper'

# Characterization of unresolved LOGIC-05 destruction failures, not an accepted
# retention/retry contract. Revisit these observations when recovery is designed;
# a passing example does not mean that retained terminal ciphertext is acceptable.
RSpec.describe 'API secret recovery fault evidence', type: :integration, recovery_characterization: true do
  before(:all) { Onetime.boot! :test }

  [:reveal!, :revealed!, :burned!].each do |operation|
    describe operation do
      let(:terminal_state) { operation == :burned! ? 'burned' : 'revealed' }

      it 'documents the unresolved retained-ciphertext outcome when destruction itself raises' do
        receipt, secret = Onetime::Receipt.spawn_pair(nil, 3600, 'destruction failure fixture')
        expires_at = secret.dbclient.call('PEXPIRETIME', secret.dbkey)
        allow(secret).to receive(:destroy!).and_raise(IOError, 'injected destruction failure')
        returned = :no_result

        expect { returned = secret.public_send(operation) }
          .to raise_error(IOError, 'injected destruction failure')

        expect(returned).to eq(:no_result)
        expect(secret).to have_received(:destroy!).once
        expect(secret.state).to eq(terminal_state)
        expect(secret.ciphertext).to be_nil
        stored = Onetime::Secret.load(secret.identifier)
        expect(stored.state).to eq(terminal_state)
        expect(stored.viewable?).to be(false)
        expect(stored.dbclient.hget(stored.dbkey, 'ciphertext')).not_to be_nil
        expect(stored.dbclient.call('PEXPIRETIME', stored.dbkey)).to eq(expires_at)
        expect(Onetime::Receipt.load(receipt.identifier).state).to eq(terminal_state)
        expect(stored.public_send(operation)).to be_falsey
      end

      it 'documents destruction failure superseding a receipt failure while retaining its exception cause' do
        receipt, secret = Onetime::Receipt.spawn_pair(nil, 3600, 'double failure fixture')
        receipt_error = IOError.new('injected receipt failure')
        cascade = operation == :burned! ? :burned! : :revealed!
        allow(secret).to receive(:load_receipt).and_return(receipt)
        allow(receipt).to receive(cascade).and_raise(receipt_error)
        allow(secret).to receive(:destroy!).and_raise(IOError, 'injected destruction failure')

        expect { secret.public_send(operation) }
          .to raise_error(IOError, 'injected destruction failure') { |error| expect(error.cause).to eq(receipt_error) }

        expect(secret).to have_received(:destroy!).once
        stored = Onetime::Secret.load(secret.identifier)
        expect(stored.state).to eq(terminal_state)
        expect(stored.viewable?).to be(false)
        expect(stored.dbclient.hget(stored.dbkey, 'ciphertext')).not_to be_nil
        expect(Onetime::Receipt.load(receipt.identifier).state).to eq('new')
      end
    end
  end
end
