# apps/api/v2/spec/models/secret_v1_v2_reveal_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')

RSpec.describe Onetime::Secret, 'v1/v2 reveal paths' do
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
      let(:ciphertext_double) do
        instance_double('Familia::EncryptedField').tap do |ct|
          allow(ct).to receive(:to_s).and_return('encrypted-blob')
          allow(ct).to receive(:reveal).and_yield(secret_value).and_return(secret_value)
        end
      end

      before do
        secret.instance_variable_set(:@ciphertext, ciphertext_double)
        # Ensure value is empty (v2 secrets don't use value field)
        secret.instance_variable_set(:@value, nil)
      end

      it 'returns the plaintext via ciphertext.reveal' do
        expect(secret.decrypted_secret_value).to eq(secret_value)
      end

      it 'calls reveal on the ciphertext field' do
        secret.decrypted_secret_value
        expect(ciphertext_double).to have_received(:reveal)
      end
    end

    context 'v1 secret (value field, legacy encryption)' do
      before do
        # Simulate v1 secret: data in value, no ciphertext
        secret.instance_variable_set(:@ciphertext, nil)
        secret.encrypt_value(secret_value)
      end

      it 'returns the plaintext via decrypted_value' do
        expect(secret.decrypted_secret_value).to eq(secret_value)
      end
    end

    context 'v1 secret without passphrase - nil vs empty string (v0.23→v0.24 migration regression)' do
      # In v0.23.3, secrets without a passphrase had @passphrase_temp = nil
      # because handle_passphrase returned early when passphrase was empty.
      # In v0.24.0, RevealSecret sets @passphrase = params['passphrase'].to_s
      # which produces "" (empty string) instead of nil. This changes the
      # encryption key derivation:
      #   nil:    SHA256("global_secret:identifier")     — nil compacted out
      #   "":     SHA256("global_secret:identifier:")     — trailing colon
      # The fix normalizes empty passphrase to nil in decrypted_secret_value.

      before do
        # Simulate v1 secret encrypted WITHOUT a passphrase (passphrase_temp was nil)
        secret.instance_variable_set(:@ciphertext, nil)
        secret.instance_variable_set(:@passphrase_temp, nil)
        secret.encrypt_value(secret_value)
        # Clear temp after encryption to simulate fresh reveal
        secret.instance_variable_set(:@passphrase_temp, nil)
      end

      it 'decrypts when passphrase: nil (default)' do
        expect(secret.decrypted_secret_value).to eq(secret_value)
      end

      it 'decrypts when passphrase_input: "" (empty string from params)' do
        # This is the exact scenario from the bug: params['passphrase'].to_s => ""
        expect(secret.decrypted_secret_value(passphrase_input: '')).to eq(secret_value)
      end

      it 'normalizes empty passphrase to nil in passphrase_temp' do
        secret.decrypted_secret_value(passphrase_input: '')
        expect(secret.passphrase_temp).to be_nil
      end

      it 'preserves non-empty passphrase in passphrase_temp' do
        # For passphrase-protected secrets, the passphrase must be preserved
        secret.instance_variable_set(:@passphrase_temp, 'real-passphrase')
        secret.encrypt_value(secret_value)
        secret.instance_variable_set(:@passphrase_temp, nil)

        secret.decrypted_secret_value(passphrase_input: 'real-passphrase')
        expect(secret.passphrase_temp).to eq('real-passphrase')
      end

      it 'proves nil and empty string produce different encryption keys without the fix' do
        # This test documents WHY the fix is necessary
        key_with_nil = Onetime::Secret.encryption_key(OT.global_secret, secret.identifier, nil)
        key_with_empty = Onetime::Secret.encryption_key(OT.global_secret, secret.identifier, '')
        expect(key_with_nil).not_to eq(key_with_empty)
      end
    end

    context 'v1 secret with passphrase' do
      let(:passphrase) { 'my-secret-passphrase' }

      before do
        secret.instance_variable_set(:@ciphertext, nil)
        # Set passphrase before encrypting so it's part of the encryption key
        secret.instance_variable_set(:@passphrase_temp, passphrase)
        secret.encrypt_value(secret_value)
        secret.update_passphrase!(passphrase)
        # Clear temp to simulate fresh reveal attempt
        secret.instance_variable_set(:@passphrase_temp, nil)
      end

      it 'decrypts with correct passphrase via keyword arg' do
        expect(secret.decrypted_secret_value(passphrase_input: passphrase)).to eq(secret_value)
      end

      it 'sets passphrase_temp internally when passphrase_input kwarg is provided' do
        # The passphrase_input: kwarg should set @passphrase_temp before calling decrypted_value
        secret.decrypted_secret_value(passphrase_input: passphrase)
        expect(secret.passphrase_temp).to eq(passphrase)
      end

      it 'fails with incorrect passphrase' do
        expect { secret.decrypted_secret_value(passphrase_input: 'wrong-passphrase') }.to raise_error(OpenSSL::Cipher::CipherError)
      end

      it 'fails when no passphrase is provided for passphrase-protected secret' do
        # Without passphrase, the encryption key derivation differs, so decryption fails
        expect { secret.decrypted_secret_value }.to raise_error(OpenSSL::Cipher::CipherError)
      end
    end

    context 'neither field present' do
      before do
        secret.instance_variable_set(:@ciphertext, nil)
        secret.instance_variable_set(:@value, nil)
        secret.instance_variable_set(:@value_encryption, nil)
      end

      it 'returns nil' do
        expect(secret.decrypted_secret_value).to be_nil
      end
    end

    context 'prefers ciphertext over value when both present' do
      let(:ciphertext_double) do
        instance_double('Familia::EncryptedField').tap do |ct|
          allow(ct).to receive(:to_s).and_return('encrypted-blob')
          allow(ct).to receive(:reveal).and_yield('v2-plaintext').and_return('v2-plaintext')
        end
      end

      before do
        secret.instance_variable_set(:@ciphertext, ciphertext_double)
        secret.encrypt_value('v1-plaintext')
      end

      it 'uses ciphertext (v2) path' do
        expect(secret.decrypted_secret_value).to eq('v2-plaintext')
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

    context 'v1 secret (value only)' do
      before do
        allow(secret).to receive(:key?).with(:value).and_return(true)
        allow(secret).to receive(:key?).with(:ciphertext).and_return(false)
      end

      it 'returns true for new state' do
        expect(secret.viewable?).to be true
      end

      it 'returns true for previewed state' do
        secret.instance_variable_set(:@state, 'previewed')
        expect(secret.viewable?).to be true
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
        secret.instance_variable_set(:@value, nil)
      end

      it 'returns true' do
        expect(secret.valid?).to be true
      end
    end

    context 'v1 secret with value' do
      before do
        secret.instance_variable_set(:@ciphertext, nil)
        secret.encrypt_value(secret_value)
      end

      it 'returns true' do
        expect(secret.valid?).to be true
      end
    end

    context 'neither field present' do
      before do
        secret.instance_variable_set(:@ciphertext, nil)
        secret.instance_variable_set(:@value, nil)
        secret.instance_variable_set(:@value_encryption, nil)
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
        secret.instance_variable_set(:@value, nil)
      end

      it 'returns true' do
        expect(secret.can_decrypt?).to be true
      end
    end

    context 'v1 secret with value, no passphrase' do
      before do
        secret.instance_variable_set(:@ciphertext, nil)
        secret.encrypt_value(secret_value)
      end

      it 'returns true' do
        expect(secret.can_decrypt?).to be true
      end
    end

    context 'secret with passphrase but no temp passphrase' do
      before do
        secret.encrypt_value(secret_value)
        secret.update_passphrase!('test-pass')
        secret.instance_variable_set(:@passphrase_temp, nil)
      end

      it 'returns false' do
        expect(secret.can_decrypt?).to be false
      end
    end
  end

  describe 'encryption key derivation uses identifier' do
    # Encryption keys are derived from `identifier` (the objid field value),
    # matching v0.23.3's `self.key` which was the identifier field value
    # (a 31-char random string), NOT the full Redis key (dbkey).

    it 'encryption_key_v2 uses identifier' do
      key_v2 = secret.encryption_key_v2

      expected = Onetime::Secret.encryption_key(OT.global_secret, secret.identifier, secret.passphrase_temp)
      expect(key_v2).to eq(expected)
    end

    it 'encryption_key_v1 uses identifier' do
      key_v1 = secret.encryption_key_v1

      expected = Onetime::Secret.encryption_key(secret.identifier, secret.passphrase_temp)
      expect(key_v1).to eq(expected)
    end

    it 'encryption_key_v2_with_nil uses identifier' do
      key_nil = secret.encryption_key_v2_with_nil

      expected = Onetime::Secret.encryption_key(nil, secret.identifier, secret.passphrase_temp)
      expect(key_nil).to eq(expected)
    end

    it 'dbkey differs from identifier (prefix:identifier:suffix format)' do
      expect(secret.dbkey).not_to eq(secret.identifier)
      expect(secret.dbkey).to include(secret.identifier)
      expect(secret.dbkey).to start_with('secret:')
    end

    it 'encrypt/decrypt roundtrip works with identifier-based keys' do
      secret.encrypt_value(secret_value)

      expect(secret.decrypted_value).to eq(secret_value)

      # Verify that decryption with dbkey-derived key would fail
      wrong_key = Onetime::Secret.encryption_key(OT.global_secret, secret.dbkey, nil)
      expect {
        secret.value.dup.force_encoding('utf-8').decrypt(key: wrong_key)
      }.to raise_error(OpenSSL::Cipher::CipherError),
        'Decrypting with dbkey-based key must fail (identifier was used for encryption)'
    end

  end
end
