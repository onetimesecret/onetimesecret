# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'V2/V3 secret cleanup regressions', type: :integration do
  before(:all) { Onetime.boot! :test }

  describe 'post-claim secret cleanup' do
    [:reveal!, :revealed!, :burned!].each do |operation|
      [:load, :transition].each do |failure|
        it "destroys a won #{operation} secret when receipt #{failure} fails, without returning success" do
          receipt, secret = Onetime::Receipt.spawn_pair(nil, 3600, 'cleanup fixture')
          if failure == :load
            allow(secret).to receive(:load_receipt).and_raise(IOError, 'injected receipt failure')
          else
            allow(secret).to receive(:load_receipt).and_return(receipt)
            cascade = operation == :burned! ? :burned! : :revealed!
            allow(receipt).to receive(cascade).and_raise(IOError, 'injected receipt failure')
          end

          expect { secret.public_send(operation) }.to raise_error(IOError, 'injected receipt failure')
          expect(Onetime::Secret.load(secret.identifier)).to be_nil
          expect(secret.state).to eq(operation == :burned! ? 'burned' : 'revealed')
          expect(secret.ciphertext).to be_nil
          expect(secret.instance_variable_get(:@passphrase_temp)).to be_nil
          expect(secret.viewable?).to be(false)
        end
      end
    end

    it 'still returns plaintext once and destroys the secret on a normal reveal' do
      receipt, secret = Onetime::Receipt.spawn_pair(nil, 3600, 'normal reveal fixture')
      loser = Onetime::Secret.load(secret.identifier)
      expect(secret.reveal!).to eq('normal reveal fixture')
      expect(loser.reveal!).to be_nil
      expect(Onetime::Secret.load(secret.identifier)).to be_nil
      expect(Onetime::Receipt.load(receipt.identifier).state).to eq('revealed')
    end

    it 'retains ciphertext and restores the claim when recipient decryption fails' do
      receipt, secret = Onetime::Receipt.spawn_pair(nil, 3600, 'decrypt fixture')
      allow(secret).to receive(:decrypted_secret_value).and_raise(Familia::EncryptionError, 'injected decrypt failure')
      expect { secret.reveal! }.to raise_error(Onetime::SecretUndecryptable)
      fresh = Onetime::Secret.load(secret.identifier)
      expect(fresh.state).to eq('new')
      expect(fresh.decrypted_secret_value).to eq('decrypt fixture')
      expect(Onetime::Receipt.load(receipt.identifier).state).to eq('new')
    end
  end
end
