# spec/support/model_test_helper.rb

module ModelTestHelper
  # Factory method to create a fully stubbed V1::Secret instance
  def create_stubbed_secret(attributes = {})
    secret = V1::Secret.new

    # Apply default test attributes
    default_attrs = {
      key: "test-secret-key-#{SecureRandom.hex(8)}",
      state: "new",
      value: nil,
      value_encryption: 2,
      passphrase: nil,
      passphrase_encryption: nil,
      custid: "test-customer-id",
    }

    # Apply attributes to the secret
    merged_attrs = default_attrs.merge(attributes)
    merged_attrs.each do |attr, value|
      secret.instance_variable_set(:"@#{attr}", value)
    end

    # Stub key persistence methods
    allow(secret).to receive(:save).and_return(true)
    allow(secret).to receive(:exists?).and_return(true)
    allow(secret).to receive(:destroy!).and_return(true)

    # Stub field setter methods that interact with Redis
    allow(secret).to receive(:passphrase!).and_return(true)
    allow(secret).to receive(:passphrase_encryption!).and_return(true)
    allow(secret).to receive(:state!).and_return(true)
    allow(secret).to receive(:value!).and_return(true)
    allow(secret).to receive(:value_encryption!).and_return(true)

    # Allow real encryption/decryption to work (it doesn't use Redis)
    # Don't use and_call_original for update_passphrase! as it calls passphrase!
    allow(secret).to receive(:update_passphrase!).and_wrap_original do |original, val|
      secret.instance_variable_set(:@passphrase, BCrypt::Password.create(val, cost: 12).to_s)
      secret.instance_variable_set(:@passphrase_encryption, "1")
      secret.instance_variable_set(:@passphrase_temp, val)
      true
    end
    allow(secret).to receive(:encrypt_value).and_call_original
    allow(secret).to receive(:decrypted_value).and_call_original

    # Implement passphrase? behavior correctly
    allow(secret).to receive(:passphrase?).and_wrap_original do |original, guess|
      return false if secret.passphrase.to_s.empty?
      begin
        ret = BCrypt::Password.new(secret.passphrase) == guess
        secret.instance_variable_set(:@passphrase_temp, guess) if ret
        ret
      rescue BCrypt::Errors::InvalidHash
        # Fall back to simple comparison for invalid hash
        (!guess.to_s.empty? && secret.passphrase.to_s.downcase.strip == guess.to_s.downcase.strip)
      end
    end

    # Implement has_passphrase? behavior
    allow(secret).to receive(:has_passphrase?).and_wrap_original do |original|
      !secret.passphrase.to_s.empty?
    end

    # Return the stubbed object
    secret
  end

  # Factory method for V1::Metadata
  def create_stubbed_metadata(attributes = {})
    metadata = V1::Metadata.new

    # Default attributes
    default_attrs = {
      key: "test-metadata-key-#{SecureRandom.hex(8)}",
      state: "new",
      secret_key: nil,
      custid: "test-customer-id",
    }

    # Apply attributes
    merged_attrs = default_attrs.merge(attributes)
    merged_attrs.each do |attr, value|
      metadata.instance_variable_set(:"@#{attr}", value)
    end

    # Stub persistence methods
    allow(metadata).to receive(:save).and_return(true)
    allow(metadata).to receive(:exists?).and_return(true)
    allow(metadata).to receive(:destroy!).and_return(true)

    # Stub field setters
    allow(metadata).to receive(:secret_key!).and_return(true)
    allow(metadata).to receive(:state!).and_return(true)

    metadata
  end

  # Creates a linked pair of V1::Secret and V1::Metadata
  def create_stubbed_secret_pair(attributes = {})
    secret_key = "test-secret-key-#{SecureRandom.hex(8)}"
    metadata_key = "test-metadata-key-#{SecureRandom.hex(8)}"

    # Extract and separate metadata and secret attributes
    metadata_attrs = {}
    secret_attrs = {}
    attributes.each do |key, value|
      metadata_attrs[key] = value
      secret_attrs[key] = value
    end

    metadata = create_stubbed_metadata(
      metadata_attrs.merge(
        key: metadata_key,
        secret_key: secret_key,
      ),
    )

    secret = create_stubbed_secret(
      secret_attrs.merge(
        key: secret_key,
        metadata_key: metadata_key,
      ),
    )

    # Link them
    allow(secret).to receive(:load_metadata).and_return(metadata)

    [metadata, secret]
  end
  # Factory method to create a fully stubbed V2::Secret instance
  def create_stubbed_onetime_secret(attributes = {})
    secret = V2::Secret.new

    # Apply default test attributes
    default_attrs = {
      key: "test-secret-key-#{SecureRandom.hex(8)}",
      state: "new",
      value: nil,
      value_encryption: 2,
      passphrase: nil,
      passphrase_encryption: nil,
      custid: "test-customer-id",
    }

    # Apply attributes to the secret
    merged_attrs = default_attrs.merge(attributes)
    merged_attrs.each do |attr, value|
      secret.instance_variable_set(:"@#{attr}", value)
    end

    # Stub key persistence methods
    allow(secret).to receive(:save).and_return(true)
    allow(secret).to receive(:exists?).and_return(true)
    allow(secret).to receive(:destroy!).and_return(true)

    # Stub field setter methods that interact with Redis
    allow(secret).to receive(:passphrase!).and_return(true)
    allow(secret).to receive(:passphrase_encryption!).and_return(true)
    allow(secret).to receive(:state!).and_return(true)
    allow(secret).to receive(:value!).and_return(true)
    allow(secret).to receive(:value_encryption!).and_return(true)

    # Allow real encryption/decryption to work (it doesn't use Redis)
    # Don't use and_call_original for update_passphrase! as it calls passphrase!
    allow(secret).to receive(:update_passphrase!).and_wrap_original do |original, val|
      secret.instance_variable_set(:@passphrase, BCrypt::Password.create(val, cost: 12).to_s)
      secret.instance_variable_set(:@passphrase_encryption, "1")
      secret.instance_variable_set(:@passphrase_temp, val)
      true
    end
    allow(secret).to receive(:encrypt_value).and_call_original
    allow(secret).to receive(:decrypted_value).and_call_original

    # Implement passphrase? behavior correctly
    allow(secret).to receive(:passphrase?).and_wrap_original do |original, guess|
      return false if secret.passphrase.to_s.empty?
      begin
        ret = BCrypt::Password.new(secret.passphrase) == guess
        secret.instance_variable_set(:@passphrase_temp, guess) if ret
        ret
      rescue BCrypt::Errors::InvalidHash
        # Fall back to simple comparison for invalid hash
        (!guess.to_s.empty? && secret.passphrase.to_s.downcase.strip == guess.to_s.downcase.strip)
      end
    end

    # Implement has_passphrase? behavior
    allow(secret).to receive(:has_passphrase?).and_wrap_original do |original|
      !secret.passphrase.to_s.empty?
    end

    # Mock the fallback secret methods
    allow(secret).to receive(:has_fallback_secrets?).and_return(false)
    allow(secret).to receive(:try_fallback_secrets).and_return(nil)

    # Return the stubbed object
    secret
  end

  # Factory method for V2::Metadata
  def create_stubbed_onetime_metadata(attributes = {})
    metadata = V2::Metadata.new

    # Default attributes
    default_attrs = {
      key: "test-metadata-key-#{SecureRandom.hex(8)}",
      state: "new",
      secret_key: nil,
      custid: "test-customer-id",
    }

    # Apply attributes
    merged_attrs = default_attrs.merge(attributes)
    merged_attrs.each do |attr, value|
      metadata.instance_variable_set(:"@#{attr}", value)
    end

    # Stub persistence methods
    allow(metadata).to receive(:save).and_return(true)
    allow(metadata).to receive(:exists?).and_return(true)
    allow(metadata).to receive(:destroy!).and_return(true)

    # Stub field setters
    allow(metadata).to receive(:secret_key!).and_return(true)
    allow(metadata).to receive(:state!).and_return(true)
    allow(metadata).to receive(:passphrase!).and_return(true)

    # Implement has_passphrase? behavior
    allow(metadata).to receive(:has_passphrase?).and_wrap_original do |original|
      !metadata.passphrase.to_s.empty?
    end

    metadata
  end

  # Creates a linked pair of V2::Secret and V2::Metadata
  def create_stubbed_onetime_secret_pair(attributes = {})
    secret_key = "test-secret-key-#{SecureRandom.hex(8)}"
    metadata_key = "test-metadata-key-#{SecureRandom.hex(8)}"

    # Extract and separate metadata and secret attributes
    metadata_attrs = {}
    secret_attrs = {}
    attributes.each do |key, value|
      metadata_attrs[key] = value
      secret_attrs[key] = value
    end

    metadata = create_stubbed_onetime_metadata(
      metadata_attrs.merge(
        key: metadata_key,
        secret_key: secret_key,
      ),
    )

    secret = create_stubbed_onetime_secret(
      secret_attrs.merge(
        key: secret_key,
        metadata_key: metadata_key,
      ),
    )

    # Link them
    allow(secret).to receive(:load_metadata).and_return(metadata)

    [metadata, secret]
  end
end

RSpec.configure do |config|
  config.include ModelTestHelper
end
