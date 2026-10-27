# spec/unit/onetime/paseto/keyring_spec.rb
#
# frozen_string_literal: true

# Key derivation and rotation for the v3 API bearer tokens (#2427). Pure: the
# keyring is a function of SECRET and SECRET_PREVIOUS, no boot, no datastore.
#
# Run: pnpm run test:rspec spec/unit/onetime/paseto/keyring_spec.rb

require 'spec_helper'
require 'onetime/paseto'

RSpec.describe Onetime::Paseto::Keyring do
  let(:secret)   { 'decafbad' * 8 }
  let(:previous) { 'cafef00d' * 8 }
  let(:older)    { 'feedface' * 8 }

  describe '.derive' do
    it 'is deterministic: the same SECRET always yields the same signing key' do
      a = described_class.derive(secret)
      b = described_class.derive(secret)

      expect(a.signing_key.kid).to eq(b.signing_key.kid)
      expect(a.signing_key.public_key.raw_public_key).to eq(b.signing_key.public_key.raw_public_key)
    end

    it 'separates the signing seed from the other HKDF purposes' do
      seed = Onetime::KeyDerivation.derive(secret, :paseto_signing)

      expect(seed.bytesize).to eq(32)
      expect(seed).not_to eq(Onetime::KeyDerivation.derive(secret, :familia_enc))
      expect(seed).not_to eq(Onetime::KeyDerivation.derive(secret, :identifier))
    end

    it 'yields a different key for a different SECRET' do
      expect(described_class.derive(secret).signing_key.kid)
        .not_to eq(described_class.derive(previous).signing_key.kid)
    end

    it 'refuses an empty SECRET' do
      expect { described_class.derive('') }.to raise_error(ArgumentError)
      expect { described_class.derive(nil) }.to raise_error(ArgumentError)
    end

    context 'without SECRET_PREVIOUS' do
      subject(:keyring) { described_class.derive(secret, nil) }

      it 'accepts exactly the current key' do
        expect(keyring.kids).to eq([keyring.signing_key.kid])
      end
    end

    context 'with SECRET_PREVIOUS (oldest first, as ConfigureFamilia reads it)' do
      subject(:keyring) { described_class.derive(secret, " #{older}, #{previous} ,,") }

      it 'signs with the current SECRET only' do
        expect(keyring.signing_key.kid).to eq(described_class.derive(secret).signing_key.kid)
        expect(keyring.signing_key).to be_signing
      end

      it 'accepts every previous key for verification, verify-only' do
        %w[older previous].each do |name|
          kid = described_class.derive(public_send(name)).signing_key.kid
          key = keyring.verification_key(kid)
          expect(key).not_to be_nil, name
          expect(key).not_to be_signing, name
        end
        expect(keyring.kids.size).to eq(3)
      end

      it 'lists the current kid first' do
        expect(keyring.kids.first).to eq(keyring.signing_key.kid)
      end

      it 'collapses a previous SECRET equal to the current one' do
        same = described_class.derive(secret, secret)
        expect(same.kids).to eq([same.signing_key.kid])
      end
    end
  end

  describe '#verification_key' do
    subject(:keyring) { described_class.derive(secret) }

    it 'answers a verification-only copy for the signing kid' do
      key = keyring.verification_key(keyring.signing_key.kid)
      expect(key).not_to be_signing
      expect(key.public_key.raw_public_key).to eq(keyring.signing_key.public_key.raw_public_key)
    end

    it 'answers nil for an unknown or nil kid' do
      expect(keyring.verification_key('0000000000000000')).to be_nil
      expect(keyring.verification_key(nil)).to be_nil
    end
  end

  describe 'key identifiers' do
    it 'are the first 16 hex characters of SHA-256 over the raw public key' do
      key = described_class.derive(secret).signing_key
      expect(key.kid).to eq(Digest::SHA256.hexdigest(key.public_key.raw_public_key)[0, 16])
      expect(key.kid).to match(/\A[0-9a-f]{16}\z/)
    end
  end

  describe 'redaction' do
    subject(:keyring) { described_class.derive(secret, previous) }

    it 'never prints key material from inspect or to_s' do
      texts = [keyring.inspect, keyring.to_s, keyring.signing_key.inspect, keyring.signing_key.to_s]
      raw   = keyring.signing_key.private_key.raw_private_key.unpack1('H*')

      texts.each do |text|
        expect(text).not_to include(raw)
        expect(text).not_to include('OpenSSL::PKey')
        expect(text).to include(keyring.signing_key.kid)
      end
    end

    it 'is frozen once built' do
      expect(keyring).to be_frozen
    end
  end

  describe 'Runtime::Security carries the keyring' do
    it 'defaults to nil and merges in through update_security' do
      state = Onetime::Runtime::Security.default
      expect(state.paseto_keyring).to be_nil
      expect(state.global_secret).to be_nil

      merged = Onetime::Runtime::Security.new(**state.to_h, paseto_keyring: described_class.derive(secret))
      expect(merged.paseto_keyring).to be_a(described_class)
    end
  end
end
