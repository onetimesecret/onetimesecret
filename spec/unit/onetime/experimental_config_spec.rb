# spec/unit/onetime/experimental_config_spec.rb

require 'openssl'

require_relative '../../spec_helper'
require_relative '../../support/boot_context'

RSpec.describe "Experimental config settings" do
  let(:source_config_path) { File.expand_path(File.join(Onetime::HOME, 'tests', 'unit', 'ruby', 'config.test.yaml')) }

  describe "allow_nil_global_secret" do
    let(:test_value) { "This is a test secret value" }
    let(:passphrase) { "testpassphrase" }
    let(:regular_secret) { "regular-secret-key" }
    let(:nil_secret) { nil }

    # Set up a mutable state hash that we can modify in tests
    let(:state_hash) { { global_secret: nil } }

    before(:each) do
      # Mock OT.state to return our mutable state hash
      allow(OT).to receive(:state).and_return(state_hash)
    end

    after(:each) do
      # Clean up state after each test
      state_hash.clear
    end

    context "when allow_nil_global_secret is false (default)" do
      before do
        # Mock OT.conf to return our test configuration
        allow(OT).to receive(:conf).and_return({
          experimental: { allow_nil_global_secret: false }
        })
      end

      it "successfully encrypts and decrypts with a non-nil global secret" do
        # Create a new secret instance for this test
        secret = TestSecret.new
        secret.key = "regular_key_test"

        # Set a non-nil global secret
        state_hash[:global_secret] = regular_secret

        # Manually construct this secret to simulate it was encrypted with a regular global secret
        secret.passphrase_temp = passphrase
        encryption_key = TestSecret.encryption_key(regular_secret, secret.key, passphrase)
        secret.value = test_value.encrypt(key: encryption_key)
        secret.value_encryption = 2

        # Decrypt with the same global secret
        secret.passphrase_temp = passphrase
        expect(secret.decrypted_value).to eq(test_value)
      end

      it "raises CipherError when decrypting with nil global secret" do
        # Create a new secret instance for this test
        secret = TestSecret.new
        secret.key = "error_key_test"

        # First encrypt with a non-nil global secret
        state_hash[:global_secret] = regular_secret

        # Manually construct this secret to simulate it was encrypted with a regular global secret
        secret.passphrase_temp = passphrase
        encryption_key = TestSecret.encryption_key(regular_secret, secret.key, passphrase)
        secret.value = test_value.encrypt(key: encryption_key)
        secret.value_encryption = 2

        # Then try to decrypt with a nil global secret
        state_hash[:global_secret] = nil
        secret.passphrase_temp = passphrase

        expect { secret.decrypted_value }.to raise_error(OpenSSL::Cipher::CipherError)
      end
    end

    context "when allow_nil_global_secret is true" do
      before do
        # Mock OT.conf to return our test configuration with allow_nil_global_secret set to true
        allow(OT).to receive(:conf).and_return({
          experimental: { allow_nil_global_secret: true }
        })
      end

      it "successfully encrypts and decrypts with a non-nil global secret" do
        # Create a completely new secret instance for this test
        secret = TestSecret.new
        secret.key = "special_test_key"

        # Set a non-nil global secret
        state_hash[:global_secret] = regular_secret

        # Set passphrase for encryption
        secret.passphrase_temp = passphrase

        # Encrypt with the non-nil global secret
        secret.encrypt_value(test_value, passphrase: passphrase)

        # Verify the encryption works
        expect(secret.value).not_to be_nil

        # Ensure decryption works with the same passphrase and global secret
        secret.passphrase_temp = passphrase
        expect(secret.decrypted_value).to eq(test_value)
      end

      it "successfully encrypts with nil global secret and decrypts with nil global secret" do
        # Create a new secret instance for this test
        secret = TestSecret.new
        secret.key = "nil_encryption_key"

        # Set nil global secret
        state_hash[:global_secret] = nil

        # Set passphrase for encryption
        secret.passphrase_temp = passphrase

        # Manually construct this secret to simulate it was encrypted with a nil global secret
        encryption_key = TestSecret.encryption_key(nil, secret.key, passphrase)
        secret.value = test_value.encrypt(key: encryption_key)
        secret.value_encryption = 2

        # Verify the encryption worked
        expect(secret.value).not_to be_nil

        # Decrypt with nil global secret
        secret.passphrase_temp = passphrase
        expect(secret.decrypted_value).to eq(test_value)
      end

      it "successfully decrypts a regular-secret-encrypted value with nil global secret" do
        # Create a new secret instance for this test
        secret = TestSecret.new
        secret.key = "special_fallback_key"

        # First encrypt with a non-nil global secret
        state_hash[:global_secret] = regular_secret

        # Manually construct this secret to simulate it was encrypted with a regular global secret
        secret.passphrase_temp = passphrase
        encryption_key = TestSecret.encryption_key(regular_secret, secret.key, passphrase)
        secret.value = test_value.encrypt(key: encryption_key)
        secret.value_encryption = 2

        # Switch to nil global secret for decryption
        state_hash[:global_secret] = nil

        # We need to know exactly what encryption key was used during encryption
        # So we can return it during the mock of encryption_key_v2_with_nil
        allow(secret).to receive(:encryption_key_v2_with_nil).and_return(encryption_key)

        # The decryption should work via the fallback mechanism
        secret.passphrase_temp = passphrase
        expect(secret.decrypted_value).to eq(test_value)
      end

      it "still raises CipherError when decrypting with wrong passphrase" do
        # Create a new secret instance for this test
        secret = TestSecret.new
        secret.key = "passphrase_test_key"

        # Set a non-nil global secret
        state_hash[:global_secret] = regular_secret

        # Manually construct this secret to simulate it was encrypted with a specific passphrase
        secret.passphrase_temp = passphrase
        encryption_key = TestSecret.encryption_key(regular_secret, secret.key, passphrase)
        secret.value = test_value.encrypt(key: encryption_key)
        secret.value_encryption = 2

        # Try decrypting with wrong passphrase
        secret.passphrase_temp = "wrong-passphrase"

        expect { secret.decrypted_value }.to raise_error(OpenSSL::Cipher::CipherError)
      end
    end

    context "when switching between nil and non-nil global secrets" do
      before do
        # Mock OT.conf to return our test configuration with allow_nil_global_secret set to true
        allow(OT).to receive(:conf).and_return({
          experimental: { allow_nil_global_secret: true }
        })
      end

      it "fails to decrypt values encrypted with non-nil secret using nil secret without special handling" do
        # Create a new secret instance for this test
        secret = TestSecret.new
        secret.key = "no_fallback_key"

        # First encrypt with a non-nil global secret
        state_hash[:global_secret] = regular_secret

        # Manually construct this secret to simulate it was encrypted with a regular global secret
        secret.passphrase_temp = passphrase
        encryption_key = TestSecret.encryption_key(regular_secret, secret.key, passphrase)
        secret.value = test_value.encrypt(key: encryption_key)
        secret.value_encryption = 2

        # Then try to decrypt with a nil global secret
        state_hash[:global_secret] = nil

        # Mock the fallback mechanism to fail
        allow(secret).to receive(:encryption_key_v2_with_nil).and_raise(OpenSSL::Cipher::CipherError)

        # Decryption should fail with CipherError
        secret.passphrase_temp = passphrase
        expect { secret.decrypted_value }.to raise_error(OpenSSL::Cipher::CipherError)
      end

      it "fails to decrypt values encrypted with nil secret using non-nil secret" do
        # Create a new secret instance for this test
        secret = TestSecret.new
        secret.key = "nil_secret_key"

        # First encrypt with a nil global secret
        state_hash[:global_secret] = nil

        # Generate the encryption key with nil global secret
        secret.passphrase_temp = passphrase

        # Manually construct this secret to simulate it was encrypted with a nil global secret
        encryption_key = TestSecret.encryption_key(nil, secret.key, passphrase)
        secret.value = test_value.encrypt(key: encryption_key)
        secret.value_encryption = 2

        # Then try to decrypt with a non-nil global secret
        state_hash[:global_secret] = regular_secret

        # Mock OT.conf to disable the fallback
        allow(OT).to receive(:conf).and_return({
          experimental: { allow_nil_global_secret: false }
        })

        # The decryption should fail since the key material is different
        secret.passphrase_temp = passphrase
        expect { secret.decrypted_value }.to raise_error(OpenSSL::Cipher::CipherError)
      end
    end
  end
end
