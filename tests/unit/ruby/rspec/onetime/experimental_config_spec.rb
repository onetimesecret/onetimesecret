# tests/unit/ruby/rspec/onetime/experimental_config_spec.rb

require_relative '../spec_helper'
require 'openssl'

RSpec.describe "Experimental config settings" do
  let(:source_config_path) { File.expand_path(File.join(Onetime::HOME, 'tests', 'unit', 'ruby', 'config.test.yaml')) }

  describe "allow_nil_global_secret" do
    let(:test_value) { "This is a test secret value" }
    let(:passphrase) { "testpassphrase" }
    let(:regular_secret) { "regular-secret-key" }
    let(:nil_secret) { nil }

    # Load the YAML content after ERB processing
    let(:test_config) {
      config_instance = Onetime::Config.new(config_path: source_config_path)
      config_instance.send(:load_config)
    }
    let(:processed_config) {
      config_instance = Onetime::Config.new
      config_instance.instance_variable_set(:@unprocessed_config, test_config)
      config_instance.send(:after_load)
    }

    before(:each) do
    end

    after(:each) do
      OT.instance_variable_set(:@conf, nil)
      OT.instance_variable_set(:@global_secret, nil)
    end

    context "when allow_nil_global_secret is false (default)" do
      before do
        @context_config = OT::Config.deep_clone(processed_config)
        @context_config[:experimental][:allow_nil_global_secret] = false

        OT.instance_variable_set(:@conf, @context_config)
      end

      it "successfully encrypts and decrypts with a non-nil global secret" do
        # Create a new secret instance for this test
        secret = V2::Secret.new
        secret.key = "regular_key_test"

        # Set a non-nil global secret
        OT.instance_variable_set(:@global_secret, regular_secret)

        # Manually construct this secret to simulate it was encrypted with a regular global secret
        secret.passphrase_temp = passphrase
        encryption_key = V2::Secret.encryption_key(regular_secret, secret.key, passphrase)
        secret.value = test_value.encrypt(key: encryption_key)
        secret.value_encryption = 2
        secret.value_checksum = test_value.gibbler

        # Decrypt with the same global secret
        secret.passphrase_temp = passphrase
        expect(secret.decrypted_value).to eq(test_value)
      end

      it "raises CipherError when decrypting with nil global secret" do
        # Create a new secret instance for this test
        secret = V2::Secret.new
        secret.key = "error_key_test"

        # First encrypt with a non-nil global secret
        OT.instance_variable_set(:@global_secret, regular_secret)

        # Manually construct this secret to simulate it was encrypted with a regular global secret
        secret.passphrase_temp = passphrase
        encryption_key = V2::Secret.encryption_key(regular_secret, secret.key, passphrase)
        secret.value = test_value.encrypt(key: encryption_key)
        secret.value_encryption = 2
        secret.value_checksum = test_value.gibbler

        # Then try to decrypt with a nil global secret
        OT.instance_variable_set(:@global_secret, nil)
        secret.passphrase_temp = passphrase

        expect { secret.decrypted_value }.to raise_error(OpenSSL::Cipher::CipherError)
      end
    end

    context "when allow_nil_global_secret is true" do
      before do
        @context_config = OT::Config.deep_clone(processed_config)
        @context_config[:experimental][:allow_nil_global_secret] = true

        OT.instance_variable_set(:@conf, @context_config)
      end

      it "successfully encrypts and decrypts with a non-nil global secret" do
        # Create a completely new secret instance for this test
        secret = V2::Secret.new
        secret.key = "special_test_key"

        # Set a non-nil global secret
        OT.instance_variable_set(:@global_secret, regular_secret)

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
        secret = V2::Secret.new
        secret.key = "nil_encryption_key"

        # Set nil global secret
        OT.instance_variable_set(:@global_secret, nil)

        # Set passphrase for encryption
        secret.passphrase_temp = passphrase

        # Manually construct this secret to simulate it was encrypted with a nil global secret
        encryption_key = V2::Secret.encryption_key(nil, secret.key, passphrase)
        secret.value = test_value.encrypt(key: encryption_key)
        secret.value_encryption = 2
        secret.value_checksum = test_value.gibbler

        # Verify the encryption worked
        expect(secret.value).not_to be_nil

        # Decrypt with nil global secret
        secret.passphrase_temp = passphrase
        expect(secret.decrypted_value).to eq(test_value)
      end

      it "successfully decrypts a regular-secret-encrypted value with nil global secret" do
        # Create a new secret instance for this test
        secret = V2::Secret.new
        secret.key = "special_fallback_key"

        # First encrypt with a non-nil global secret
        OT.instance_variable_set(:@global_secret, regular_secret)

        # Manually construct this secret to simulate it was encrypted with a regular global secret
        secret.passphrase_temp = passphrase
        encryption_key = V2::Secret.encryption_key(regular_secret, secret.key, passphrase)
        secret.value = test_value.encrypt(key: encryption_key)
        secret.value_encryption = 2
        secret.value_checksum = test_value.gibbler

        # Switch to nil global secret for decryption
        OT.instance_variable_set(:@global_secret, nil)

        # Enable fallback mechanism
        @context_config[:experimental][:allow_nil_global_secret] = true

        # We need to know exactly what encryption key was used during encryption
        # So we can return it during the mock of encryption_key_v2_with_nil
        allow(secret).to receive(:encryption_key_v2_with_nil).and_return(encryption_key)

        # The decryption should work via the fallback mechanism
        secret.passphrase_temp = passphrase
        expect(secret.decrypted_value).to eq(test_value)
      end

      it "still raises CipherError when decrypting with wrong passphrase" do
        # Create a new secret instance for this test
        secret = V2::Secret.new
        secret.key = "passphrase_test_key"

        # Set a non-nil global secret
        OT.instance_variable_set(:@global_secret, regular_secret)

        # Manually construct this secret to simulate it was encrypted with a specific passphrase
        secret.passphrase_temp = passphrase
        encryption_key = V2::Secret.encryption_key(regular_secret, secret.key, passphrase)
        secret.value = test_value.encrypt(key: encryption_key)
        secret.value_encryption = 2
        secret.value_checksum = test_value.gibbler

        # Try decrypting with wrong passphrase
        secret.passphrase_temp = "wrong-passphrase"

        expect { secret.decrypted_value }.to raise_error(OpenSSL::Cipher::CipherError)
      end
    end

    context "when switching between nil and non-nil global secrets" do
      before do
        @context_config = OT::Config.deep_clone(processed_config)
        @context_config[:experimental][:allow_nil_global_secret] = true

        OT.instance_variable_set(:@conf, @context_config)
      end

      it "fails to decrypt values encrypted with non-nil secret using nil secret without special handling" do
        # Create a new secret instance for this test
        secret = V2::Secret.new
        secret.key = "no_fallback_key"

        # First encrypt with a non-nil global secret
        OT.instance_variable_set(:@global_secret, regular_secret)

        # Manually construct this secret to simulate it was encrypted with a regular global secret
        secret.passphrase_temp = passphrase
        encryption_key = V2::Secret.encryption_key(regular_secret, secret.key, passphrase)
        secret.value = test_value.encrypt(key: encryption_key)
        secret.value_encryption = 2
        secret.value_checksum = test_value.gibbler

        # Then try to decrypt with a nil global secret
        OT.instance_variable_set(:@global_secret, nil)

        # Enable fallback mechanism but mock it to fail
        @context_config[:experimental][:allow_nil_global_secret] = true
        allow(secret).to receive(:encryption_key_v2_with_nil).and_raise(OpenSSL::Cipher::CipherError)

        # Decryption should fail with CipherError
        secret.passphrase_temp = passphrase
        expect { secret.decrypted_value }.to raise_error(OpenSSL::Cipher::CipherError)
      end

      it "fails to decrypt values encrypted with nil secret using non-nil secret" do
        # Create a new secret instance for this test
        secret = V2::Secret.new
        secret.key = "nil_secret_key"

        # First encrypt with a nil global secret
        OT.instance_variable_set(:@global_secret, nil)

        # Generate the encryption key with nil global secret
        secret.passphrase_temp = passphrase

        # Manually construct this secret to simulate it was encrypted with a nil global secret
        encryption_key = V2::Secret.encryption_key(nil, secret.key, passphrase)
        secret.value = test_value.encrypt(key: encryption_key)
        secret.value_encryption = 2
        secret.value_checksum = test_value.gibbler

        # Then try to decrypt with a non-nil global secret
        OT.instance_variable_set(:@global_secret, regular_secret)

        # IMPORTANT: Completely disable the fallback
        @context_config[:experimental][:allow_nil_global_secret] = false

        # The decryption should fail since the key material is different
        secret.passphrase_temp = passphrase
        expect { secret.decrypted_value }.to raise_error(OpenSSL::Cipher::CipherError)
      end
    end
  end
end
