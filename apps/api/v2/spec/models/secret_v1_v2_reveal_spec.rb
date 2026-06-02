# apps/api/v2/spec/models/secret_v1_v2_reveal_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')

RSpec.describe Onetime::Secret, 'reveal and decryption' do
  let(:secret) { create_stubbed_onetime_secret(key: 'test-secret-key-v1v2') }
  let(:secret_value) { 'This is the plaintext secret' }

  before do
    allow(OT).to receive_messages(global_secret: 'global-test-secret', conf: {
      'development' => {
        'allow_nil_global_secret' => false,
      },
    })
  end

  describe '#decrypted_secret_value' do
    context 'v2 secret (ciphertext field)' do
      let(:binary_secret_value) { secret_value.dup.force_encoding('ASCII-8BIT') }
      let(:ciphertext_double) do
        instance_double('Familia::EncryptedField').tap do |ct|
          allow(ct).to receive(:to_s).and_return('encrypted-blob')
          allow(ct).to receive(:reveal).and_yield(binary_secret_value).and_return(binary_secret_value)
        end
      end

      before do
        secret.instance_variable_set(:@ciphertext, ciphertext_double)
      end

      it 'returns the plaintext via ciphertext.reveal' do
        expect(secret.decrypted_secret_value).to eq(secret_value)
      end

      it 'calls reveal on the ciphertext field' do
        secret.decrypted_secret_value
        expect(ciphertext_double).to have_received(:reveal)
      end

      it 'returns UTF-8 encoding even when ciphertext.reveal returns BINARY' do
        result = secret.decrypted_secret_value
        expect(result.encoding).to eq(Encoding::UTF_8),
          "Expected UTF-8 but got #{result.encoding} — JSON.generate will reject BINARY strings in json 3.0"
      end

      it 'applies force_encoding in-place without duplicating decrypted content' do
        result = secret.decrypted_secret_value
        expect(result).to equal(binary_secret_value),
          'Should be the same object (no dup) to avoid extra copies of secrets in memory'
      end

      it 'produces a string that JSON.generate accepts without warning' do
        result = secret.decrypted_secret_value
        expect { JSON.generate({ secret_value: result }) }.not_to output.to_stderr
      end
    end

    context 'no ciphertext present' do
      before do
        secret.instance_variable_set(:@ciphertext, nil)
      end

      it 'returns nil' do
        expect(secret.decrypted_secret_value).to be_nil
      end
    end
  end

  describe '#viewable?' do
    before do
      secret.instance_variable_set(:@state, 'new')
    end

    context 'v2 secret (ciphertext only)' do
      before do
        allow(secret).to receive(:key?).with(:value).and_return(false)
        allow(secret).to receive(:key?).with(:ciphertext).and_return(true)
      end

      it 'returns true for new state' do
        expect(secret.viewable?).to be true
      end

      it 'returns true for previewed state' do
        secret.instance_variable_set(:@state, 'previewed')
        expect(secret.viewable?).to be true
      end

      it 'returns false for revealed state' do
        secret.instance_variable_set(:@state, 'revealed')
        expect(secret.viewable?).to be false
      end
    end

    context 'neither field present' do
      before do
        allow(secret).to receive(:key?).with(:value).and_return(false)
        allow(secret).to receive(:key?).with(:ciphertext).and_return(false)
      end

      it 'returns false' do
        expect(secret.viewable?).to be false
      end
    end
  end

  describe '#valid?' do
    context 'v2 secret with ciphertext' do
      let(:ciphertext_double) do
        instance_double('Familia::EncryptedField').tap do |ct|
          allow(ct).to receive(:to_s).and_return('encrypted-data')
        end
      end

      before do
        secret.instance_variable_set(:@ciphertext, ciphertext_double)
      end

      it 'returns true' do
        expect(secret.valid?).to be true
      end
    end

    context 'no ciphertext' do
      before do
        secret.instance_variable_set(:@ciphertext, nil)
      end

      it 'returns false' do
        expect(secret.valid?).to be false
      end
    end
  end

  describe '#can_decrypt?' do
    context 'v2 secret with ciphertext, no passphrase' do
      let(:ciphertext_double) do
        instance_double('Familia::EncryptedField').tap do |ct|
          allow(ct).to receive(:to_s).and_return('encrypted-data')
        end
      end

      before do
        secret.instance_variable_set(:@ciphertext, ciphertext_double)
        secret.instance_variable_set(:@passphrase, nil)
      end

      it 'returns true' do
        expect(secret.can_decrypt?).to be true
      end
    end

    context 'secret with passphrase set' do
      let(:ciphertext_double) do
        instance_double('Familia::EncryptedField').tap do |ct|
          allow(ct).to receive(:to_s).and_return('encrypted-data')
        end
      end

      before do
        secret.instance_variable_set(:@ciphertext, ciphertext_double)
        secret.instance_variable_set(:@passphrase, '$argon2id$some-hash')
      end

      it 'returns false' do
        expect(secret.can_decrypt?).to be false
      end
    end

    context 'no ciphertext' do
      before do
        secret.instance_variable_set(:@ciphertext, nil)
      end

      it 'returns false' do
        expect(secret.can_decrypt?).to be false
      end
    end
  end
end
