# frozen_string_literal: true

require 'spec_helper'

# Characterization of LOGIC-05 destruction failures, not an accepted retry
# contract. When destroy! raises, the terminal record survives without its
# payload: the ciphertext field is struck before the error propagates. Revisit
# these observations when recovery is designed.
RSpec.describe 'API secret recovery fault evidence', type: :integration, recovery_characterization: true do
  before(:all) { Onetime.boot! :test }

  [:reveal!, :revealed!, :burned!].each do |operation|
    describe operation do
      let(:terminal_state) { operation == :burned! ? 'burned' : 'revealed' }

      it 'strikes the stored ciphertext and keeps the terminal record when destruction itself raises' do
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
        expect(stored.dbclient.hget(stored.dbkey, 'ciphertext')).to be_nil
        expect(stored.dbclient.call('PEXPIRETIME', stored.dbkey)).to eq(expires_at)
        expect(Onetime::Receipt.load(receipt.identifier).state).to eq(terminal_state)
        expect(stored.public_send(operation)).to be_falsey
      end

      it 'propagates the destruction error when the ciphertext strike fails too' do
        _, secret = Onetime::Receipt.spawn_pair(nil, 3600, 'strike failure fixture')
        allow(secret).to receive(:destroy!).and_raise(IOError, 'injected destruction failure')
        clients = []
        allow(secret).to receive(:dbclient).and_wrap_original do |original, *args|
          client = original.call(*args)
          allow(client).to receive(:hdel).and_raise(IOError, 'injected strike failure')
          clients << client
          client
        end

        expect { secret.public_send(operation) }.to raise_error(IOError, 'injected destruction failure')
        expect(clients.last).to have_received(:hdel).with(secret.dbkey, 'ciphertext', 'value')
      end

      it 'strikes the stored ciphertext when destruction fails after a receipt failure, keeping the exception cause' do
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
        expect(stored.dbclient.hget(stored.dbkey, 'ciphertext')).to be_nil
        expect(Onetime::Receipt.load(receipt.identifier).state).to eq('new')
      end
    end
  end
end
