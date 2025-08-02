# spec/apps/api/v2/models/secret_encryption_spec.rb

require_relative '../../../../spec_helper'

RSpec.describe V2::Secret, allow_redis: false do
  describe 'encryption functionality' do
    let(:secret_value) { "This is a secret message" }
    let(:secret) { create_stubbed_v2_secret(key: "test-secret-key-12345") }
    let(:passphrase) { "test-passphrase-123" }

    before do
      allow(OT).to receive(:global_secret).and_return("global-test-secret")
      allow(OT).to receive(:conf).and_return({
        experimental: {
          allow_nil_global_secret: false,
          rotated_secrets: []
        }
      })
    end

    describe '#encrypt_value' do
      it 'encrypts the value' do
        secret.encrypt_value(secret_value)

        expect(secret.value).not_to eq(secret_value)
        # NOTE: value_encryption is stored as integer 2, not string "2"
        expect(secret.value_encryption).to eq(2)
      end

      it 'truncates content when size limit is specified' do
        long_value = "A" * 100
        size_limit = 10

        secret.encrypt_value(long_value, size: size_limit)

        decrypted = secret.decrypted_value
        # Account for the randomized fuzzy truncation (0-20% extra)
        expect(decrypted.length).to be >= size_limit
        expect(decrypted.length).to be <= (size_limit * 1.2).to_i
        expect(secret.truncated?).to be true
      end

      it 'does not truncate when content is within size limit' do
        secret.encrypt_value(secret_value, size: 100)

        expect(secret.truncated?).to be false
        expect(secret.decrypted_value).to eq(secret_value)
      end
    end

    describe '#decrypted_value' do
      it 'returns the original value after encryption' do
        secret.encrypt_value(secret_value)

        expect(secret.decrypted_value).to eq(secret_value)
      end

      it 'handles different encryption modes' do
        # Mode 2 (current)
        secret.value_encryption = 2
        secret.encrypt_value(secret_value)
        expect(secret.decrypted_value).to eq(secret_value)

        # Mode 1 (legacy)
        allow(secret).to receive(:encryption_key_v1).and_return(Digest::SHA256.hexdigest("test-key"))
        secret.value_encryption = 1
        secret.encrypt_value(secret_value)
        expect(secret.decrypted_value).to eq(secret_value)

        # Mode 0 (unencrypted)
        secret.value_encryption = 0
        secret.value = secret_value
        expect(secret.decrypted_value).to eq(secret_value)
      end

      it 'raises error for unknown encryption mode' do
        secret.encrypt_value(secret_value)
        secret.value_encryption = 99

        expect { secret.decrypted_value }.to raise_error(RuntimeError, /Unknown encryption mode/)
      end

      it 'handles non-ASCII characters correctly' do
        unicode_value = "こんにちは世界 • ¥€$¢£"
        secret.encrypt_value(unicode_value)

        expect(secret.decrypted_value).to eq(unicode_value)
      end
    end

    describe 'encryption keys' do
      it 'generates different keys for different encryption versions' do
        v1_key = secret.encryption_key_v1
        v2_key = secret.encryption_key_v2

        expect(v1_key).not_to eq(v2_key)
      end

      it 'incorporates global secret in v2 keys' do
        allow(secret).to receive(:passphrase_temp).and_return(passphrase)

        # With passphrase
        key_with_passphrase = secret.encryption_key_v2

        # Without passphrase
        allow(secret).to receive(:passphrase_temp).and_return(nil)
        key_without_passphrase = secret.encryption_key_v2

        expect(key_with_passphrase).not_to eq(key_without_passphrase)
      end

      it 'returns consistent keys for the same inputs' do
        allow(secret).to receive(:passphrase_temp).and_return(passphrase)

        key1 = secret.encryption_key_v2
        key2 = secret.encryption_key_v2

        expect(key1).to eq(key2)
      end
    end
  end

  describe 'passphrase functionality' do
    let(:secret) { create_stubbed_v2_secret }
    let(:passphrase) { "secure-test-passphrase" }

    describe '#update_passphrase!' do
      it 'stores a BCrypt hash of the passphrase' do
        secret.update_passphrase!(passphrase)

        expect(secret.passphrase).not_to eq(passphrase)
        expect(secret.passphrase).to start_with("$2a$")
        expect(secret.passphrase_encryption).to eq("1")
      end

      it 'generates different hashes for identical passphrases' do
        secret.update_passphrase!(passphrase)
        first_hash = secret.passphrase

        secret.update_passphrase!(passphrase)
        second_hash = secret.passphrase

        expect(first_hash).not_to eq(second_hash)
      end

      it 'saves the unencrypted passphrase in memory temporarily' do
        secret.update_passphrase!(passphrase)

        expect(secret.passphrase_temp).to eq(passphrase)
      end
    end

    describe '#passphrase?' do
      it 'validates correct passphrase' do
        secret.update_passphrase!(passphrase)
        # Clear the temp storage to ensure validation logic works
        secret.instance_variable_set(:@passphrase_temp, nil)

        expect(secret.passphrase?(passphrase)).to be true
        # Check that passphrase is stored for later decryption
        expect(secret.passphrase_temp).to eq(passphrase)
      end

      it 'rejects incorrect passphrase' do
        secret.update_passphrase!(passphrase)

        expect(secret.passphrase?("wrong-passphrase")).to be false
      end

      it 'falls back to simple comparison for invalid hash' do
        # Simulate a situation with invalid BCrypt hash
        secret.passphrase = "invalid-bcrypt-hash"

        # Should fall back to simple comparison for non-BCrypt hash
        expect(secret.passphrase?("invalid-bcrypt-hash")).to be true
      end
    end

    describe '#has_passphrase?' do
      it 'returns true when passphrase exists' do
        secret.update_passphrase!(passphrase)

        expect(secret.has_passphrase?).to be true
      end

      it 'returns false when passphrase is empty' do
        secret.passphrase = ""

        expect(secret.has_passphrase?).to be false
      end

      it 'returns false when passphrase is nil' do
        secret.passphrase = nil

        expect(secret.has_passphrase?).to be false
      end
    end
  end

  describe 'secret lifecycle with encryption', allow_redis: true do
    let(:custid) { "test-customer" }
    let(:metadata_key) { "test-metadata-key" }
    let(:secret_value) { "Top secret information" }
    let(:passphrase) { "secure-passphrase" }

    describe '.spawn_pair' do
      it 'creates linked secret and metadata objects' do
        metadata, secret = create_stubbed_v2_secret_pair(custid: custid)

        expect(metadata).to be_a(V2::Metadata)
        expect(secret).to be_a(V2::Secret)
        expect(metadata.secret_key).to eq(secret.key)
        expect(secret.metadata_key).to eq(metadata.key)
        expect(metadata.custid).to eq(custid)
        expect(secret.custid).to eq(custid)
      end
    end

    describe 'state transitions' do
      let(:metadata) { create_stubbed_v2_metadata(state: "new") }
      let(:secret) { create_stubbed_v2_secret(
        metadata_key: metadata.key,
        state: "new"
      )}

      before do
        # Setup linked objects
        metadata.secret_key = secret.key

        # Mock the load_metadata method
        allow(secret).to receive(:load_metadata).and_return(metadata)

        # Encrypt the test value
        secret.encrypt_value(secret_value)
      end

      xit 'clears sensitive data when secret is received' do
        secret.received!

        # Check that sensitive data is cleared
        expect(secret.instance_variable_get(:@value)).to be_nil
        expect(secret.instance_variable_get(:@passphrase_temp)).to be_nil
        expect(secret.state).to eq("received")
        expect(metadata.state).to eq("received")
        expect(secret).to have_received(:destroy!)
      end

      it 'only transitions from new or viewed state to received' do
        secret.state = "burned"
        # Should not change state
        secret.received!
        expect(secret.state).to eq("burned")

        # Reset and try from valid state
        secret.state = "viewed"
        secret.received!
        expect(secret.state).to eq("received")
      end

      it 'marks secret as viewed without destroying it' do
        secret.viewed!

        expect(secret.state).to eq("viewed")
        expect(secret).not_to have_received(:destroy!)
      end

      xit 'clears the passphrase when burned' do
        secret.burned!

        expect(secret.instance_variable_get(:@passphrase_temp)).to be_nil
        expect(secret.state).to eq("new") # State doesn't change because destroy! is mocked
        expect(metadata.state).to eq("burned")
        expect(secret).to have_received(:destroy!)
      end
    end
  end

  describe 'security and edge cases' do
    let(:secret) { create_stubbed_v2_secret }

    it 'handles empty content' do
      secret.encrypt_value("")

      expect(secret.value_encryption).to eq(-1) # Special flag for empty content
      expect(secret.decrypted_value).to eq("")
    end

    it 'prevents decryption when no value exists' do
      expect(secret.can_decrypt?).to be false
    end

    it 'requires passphrase for decryption when passphrase is set' do
      secret.encrypt_value("test value")
      secret.update_passphrase!("test passphrase")

      # Clear the temporary passphrase to simulate passphrase not provided
      secret.instance_variable_set(:@passphrase_temp, nil)

      expect(secret.can_decrypt?).to be false

      # Set the temp passphrase to simulate provided passphrase
      secret.instance_variable_set(:@passphrase_temp, "test passphrase")

      expect(secret.can_decrypt?).to be true
    end
  end
end
