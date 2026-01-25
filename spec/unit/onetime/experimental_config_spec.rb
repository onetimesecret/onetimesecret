# spec/unit/onetime/experimental_config_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'openssl'

RSpec.describe "Experimental config settings" do
  let(:source_config_path) { File.expand_path(File.join(Onetime::HOME, 'spec', 'config.test.yaml')) }

  describe "allow_nil_global_secret" do
    let(:test_value) { "This is a test secret value" }
    let(:passphrase) { "testpassphrase" }
    let(:regular_secret) { "regular-secret-key" }
    let(:nil_secret) { nil }

    # Load the YAML content after ERB processing
    let(:test_config) { Onetime::Config.load(source_config_path) }
    let(:processed_config) { Onetime::Config.after_load(test_config) }

    # Save original state for cleanup
    let(:original_security) { Onetime::Runtime.security }
    let(:original_conf) { OT.conf }

    # Helper to set passphrase_temp on a secret (no setter method exists)
    def set_passphrase_temp(secret, val)
      secret.instance_variable_set(:@passphrase_temp, val)
    end

    before(:each) do
      # Force evaluation of original_conf before tests modify it
      original_conf
    end

    after(:each) do
      # Restore original config (not nil!)
      OT.instance_variable_set(:@conf, original_conf)
      # Restore original security state via Runtime
      Onetime::Runtime.security = original_security
    end

    context "when allow_nil_global_secret is false (default)" do
      before do
        @context_config = OT::Config.deep_clone(processed_config)
        @context_config['experimental']['allow_nil_global_secret'] = false

        OT.instance_variable_set(:@conf, @context_config)
      end

      it "successfully encrypts and decrypts with a non-nil global secret" do
        # Create a new secret instance for this test (identifier auto-generated)
        secret = Onetime::Secret.new

        # Set a non-nil global secret via Runtime
        Onetime::Runtime.update_security(global_secret: regular_secret)

        # Manually construct this secret to simulate it was encrypted with a regular global secret
        set_passphrase_temp(secret, passphrase)
        encryption_key = Onetime::Secret.encryption_key(regular_secret, secret.identifier, passphrase)
        secret.value = test_value.encrypt(key: encryption_key)
        secret.value_encryption = 2

        # Decrypt with the same global secret
        set_passphrase_temp(secret, passphrase)
        expect(secret.decrypted_value).to eq(test_value)
      end

      it "raises CipherError when decrypting with nil global secret" do
        # Create a new secret instance for this test (identifier auto-generated)
        secret = Onetime::Secret.new

        # First encrypt with a non-nil global secret
        Onetime::Runtime.update_security(global_secret: regular_secret)

        # Manually construct this secret to simulate it was encrypted with a regular global secret
        set_passphrase_temp(secret, passphrase)
        encryption_key = Onetime::Secret.encryption_key(regular_secret, secret.identifier, passphrase)
        secret.value = test_value.encrypt(key: encryption_key)
        secret.value_encryption = 2

        # Then try to decrypt with a nil global secret
        Onetime::Runtime.update_security(global_secret: nil)
        set_passphrase_temp(secret, passphrase)

        expect { secret.decrypted_value }.to raise_error(OpenSSL::Cipher::CipherError)
      end
    end

    context "when allow_nil_global_secret is true" do
      before do
        @context_config = OT::Config.deep_clone(processed_config)
        @context_config['experimental']['allow_nil_global_secret'] = true

        OT.instance_variable_set(:@conf, @context_config)
      end

      it "successfully encrypts and decrypts with a non-nil global secret" do
        # Create a completely new secret instance for this test (identifier auto-generated)
        secret = Onetime::Secret.new

        # Set a non-nil global secret via Runtime
        Onetime::Runtime.update_security(global_secret: regular_secret)

        # Set passphrase for encryption
        set_passphrase_temp(secret, passphrase)

        # Encrypt with the non-nil global secret
        secret.encrypt_value(test_value, passphrase: passphrase)

        # Verify the encryption works
        expect(secret.value).not_to be_nil

        # Ensure decryption works with the same passphrase and global secret
        set_passphrase_temp(secret, passphrase)
        expect(secret.decrypted_value).to eq(test_value)
      end

      it "successfully encrypts with nil global secret and decrypts with nil global secret" do
        # Create a new secret instance for this test (identifier auto-generated)
        secret = Onetime::Secret.new

        # Set nil global secret via Runtime
        Onetime::Runtime.update_security(global_secret: nil)

        # Set passphrase for encryption
        set_passphrase_temp(secret, passphrase)

        # Manually construct this secret to simulate it was encrypted with a nil global secret
        encryption_key = Onetime::Secret.encryption_key(nil, secret.identifier, passphrase)
        secret.value = test_value.encrypt(key: encryption_key)
        secret.value_encryption = 2

        # Verify the encryption worked
        expect(secret.value).not_to be_nil

        # Decrypt with nil global secret
        set_passphrase_temp(secret, passphrase)
        expect(secret.decrypted_value).to eq(test_value)
      end

      it "successfully decrypts a regular-secret-encrypted value with nil global secret" do
        # Create a new secret instance for this test (identifier auto-generated)
        secret = Onetime::Secret.new

        # First encrypt with a non-nil global secret
        Onetime::Runtime.update_security(global_secret: regular_secret)

        # Manually construct this secret to simulate it was encrypted with a regular global secret
        set_passphrase_temp(secret, passphrase)
        encryption_key = Onetime::Secret.encryption_key(regular_secret, secret.identifier, passphrase)
        secret.value = test_value.encrypt(key: encryption_key)
        secret.value_encryption = 2

        # Switch to nil global secret for decryption
        Onetime::Runtime.update_security(global_secret: nil)

        # Enable fallback mechanism
        @context_config['experimental']['allow_nil_global_secret'] = true

        # The wrong key that will be used for primary decryption attempt
        wrong_key = Onetime::Secret.encryption_key(nil, secret.identifier, passphrase)

        # Stub Encryptor.decrypt to fail deterministically on wrong key.
        # CBC mode only raises CipherError on padding failures, which is non-deterministic
        # (~1/256 chance of valid padding with wrong key). This ensures the fallback
        # mechanism is always exercised.
        allow(Encryptor).to receive(:decrypt).and_wrap_original do |method, *args|
          opts = args.last.is_a?(Hash) ? args.last : {}
          if opts[:key] == wrong_key
            raise OpenSSL::Cipher::CipherError.new("wrong key - simulated for test")
          end
          method.call(*args)
        end

        # Return the correct encryption key for the fallback attempt
        allow(secret).to receive(:encryption_key_v2_with_nil).and_return(encryption_key)

        # The decryption should work via the fallback mechanism
        set_passphrase_temp(secret, passphrase)
        expect(secret.decrypted_value).to eq(test_value)
      end

      it "still raises CipherError when decrypting with wrong passphrase" do
        # Create a new secret instance for this test (identifier auto-generated)
        secret = Onetime::Secret.new

        # Set a non-nil global secret via Runtime
        Onetime::Runtime.update_security(global_secret: regular_secret)

        # Manually construct this secret to simulate it was encrypted with a specific passphrase
        set_passphrase_temp(secret, passphrase)
        encryption_key = Onetime::Secret.encryption_key(regular_secret, secret.identifier, passphrase)
        secret.value = test_value.encrypt(key: encryption_key)
        secret.value_encryption = 2

        # Try decrypting with wrong passphrase
        set_passphrase_temp(secret, "wrong-passphrase")

        expect { secret.decrypted_value }.to raise_error(OpenSSL::Cipher::CipherError)
      end
    end

    context "when switching between nil and non-nil global secrets" do
      before do
        @context_config = OT::Config.deep_clone(processed_config)
        @context_config['experimental']['allow_nil_global_secret'] = true

        OT.instance_variable_set(:@conf, @context_config)
      end

      it "fails to decrypt values encrypted with non-nil secret using nil secret without special handling" do
        # Create a new secret instance for this test (identifier auto-generated)
        secret = Onetime::Secret.new

        # First encrypt with a non-nil global secret
        Onetime::Runtime.update_security(global_secret: regular_secret)

        # Manually construct this secret to simulate it was encrypted with a regular global secret
        set_passphrase_temp(secret, passphrase)
        encryption_key = Onetime::Secret.encryption_key(regular_secret, secret.identifier, passphrase)
        secret.value = test_value.encrypt(key: encryption_key)
        secret.value_encryption = 2

        # Then try to decrypt with a nil global secret
        Onetime::Runtime.update_security(global_secret: nil)

        # Enable fallback mechanism but mock it to fail
        @context_config['experimental']['allow_nil_global_secret'] = true
        allow(secret).to receive(:encryption_key_v2_with_nil).and_raise(OpenSSL::Cipher::CipherError)

        # Decryption should fail with CipherError
        set_passphrase_temp(secret, passphrase)
        expect { secret.decrypted_value }.to raise_error(OpenSSL::Cipher::CipherError)
      end

      it "fails to decrypt values encrypted with nil secret using non-nil secret" do
        # Create a new secret instance for this test (identifier auto-generated)
        secret = Onetime::Secret.new

        # First encrypt with a nil global secret
        Onetime::Runtime.update_security(global_secret: nil)

        # Generate the encryption key with nil global secret
        set_passphrase_temp(secret, passphrase)

        # Manually construct this secret to simulate it was encrypted with a nil global secret
        encryption_key = Onetime::Secret.encryption_key(nil, secret.identifier, passphrase)
        secret.value = test_value.encrypt(key: encryption_key)
        secret.value_encryption = 2

        # Then try to decrypt with a non-nil global secret
        Onetime::Runtime.update_security(global_secret: regular_secret)

        # IMPORTANT: Completely disable the fallback
        @context_config['experimental']['allow_nil_global_secret'] = false

        # The decryption should fail since the key material is different
        set_passphrase_temp(secret, passphrase)
        expect { secret.decrypted_value }.to raise_error(OpenSSL::Cipher::CipherError)
      end
    end
  end
end
