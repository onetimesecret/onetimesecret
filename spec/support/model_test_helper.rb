# spec/support/model_test_helper.rb
#
# frozen_string_literal: true

module ModelTestHelper
  # Generate a unique email address for tests
  # @param prefix [String] optional prefix for the email
  # @return [String] unique email address
  def generate_unique_test_email(prefix = "test")
    "#{prefix}_#{SecureRandom.hex(8)}_#{Familia.now.to_i}@example.com"
  end

  # Factory method to create a fully stubbed Onetime::Secret instance
  def create_stubbed_secret(attributes = {})
    secret = Onetime::Secret.new

    # Apply default test attributes
    # Note: Secret uses objid/identifier (auto-generated), not 'key'
    default_attrs = {
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
    allow(secret).to receive(:update_passphrase!).and_wrap_original do |original, val, algorithm: :argon2|
      case algorithm
      when :argon2
        secret.instance_variable_set(:@passphrase, Argon2::Password.create(val, t_cost: 1, m_cost: 5, p_cost: 1))
        secret.instance_variable_set(:@passphrase_encryption, "2")
      when :bcrypt
        secret.instance_variable_set(:@passphrase, BCrypt::Password.create(val, cost: 12).to_s)
        secret.instance_variable_set(:@passphrase_encryption, "1")
      end
      secret.instance_variable_set(:@passphrase_temp, val)
      true
    end
    allow(secret).to receive(:encrypt_value).and_call_original
    allow(secret).to receive(:decrypted_value).and_call_original

    # Implement passphrase? behavior correctly (supports both Argon2 and BCrypt)
    allow(secret).to receive(:passphrase?).and_wrap_original do |original, guess|
      next false if secret.passphrase.to_s.empty?
      begin
        ret = if secret.passphrase.to_s.start_with?('$argon2id$')
          Argon2::Password.verify_password(guess, secret.passphrase)
        else
          BCrypt::Password.new(secret.passphrase) == guess
        end
        secret.instance_variable_set(:@passphrase_temp, guess) if ret
        ret
      rescue BCrypt::Errors::InvalidHash, Argon2::ArgonHashFail
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

  # Factory method for Onetime::Metadata
  def create_stubbed_metadata(attributes = {})
    metadata = Onetime::Metadata.new

    # Default attributes
    # Note: Metadata uses objid/identifier (auto-generated), not 'key'
    # secret_identifier is the current field (secret_key is deprecated)
    default_attrs = {
      state: "new",
      secret_identifier: nil,
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
    allow(metadata).to receive(:secret_identifier!).and_return(true)
    allow(metadata).to receive(:state!).and_return(true)

    metadata
  end

  # Creates a linked pair of Onetime::Secret and Onetime::Metadata
  def create_stubbed_secret_pair(attributes = {})
    # Extract and separate metadata and secret attributes
    metadata_attrs = {}
    secret_attrs = {}
    attributes.each do |key, value|
      metadata_attrs[key] = value
      secret_attrs[key] = value
    end

    # Create the objects first (identifiers are auto-generated)
    metadata = create_stubbed_metadata(metadata_attrs)
    secret = create_stubbed_secret(secret_attrs)

    # Now link them using their auto-generated identifiers
    metadata.instance_variable_set(:@secret_identifier, secret.identifier)
    secret.instance_variable_set(:@metadata_identifier, metadata.identifier)

    # Link them
    allow(secret).to receive(:load_metadata).and_return(metadata)

    [metadata, secret]
  end
  # Factory method to create a fully stubbed Onetime::Secret instance
  def create_stubbed_onetime_secret(attributes = {})
    secret = Onetime::Secret.new

    # Apply default test attributes
    # Note: Secret uses objid/identifier (auto-generated), not 'key'
    default_attrs = {
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
    allow(secret).to receive(:update_passphrase!).and_wrap_original do |original, val, algorithm: :argon2|
      case algorithm
      when :argon2
        secret.instance_variable_set(:@passphrase, Argon2::Password.create(val, t_cost: 1, m_cost: 5, p_cost: 1))
        secret.instance_variable_set(:@passphrase_encryption, "2")
      when :bcrypt
        secret.instance_variable_set(:@passphrase, BCrypt::Password.create(val, cost: 12).to_s)
        secret.instance_variable_set(:@passphrase_encryption, "1")
      end
      secret.instance_variable_set(:@passphrase_temp, val)
      true
    end
    allow(secret).to receive(:encrypt_value).and_call_original
    allow(secret).to receive(:decrypted_value).and_call_original

    # Implement passphrase? behavior correctly (supports both Argon2 and BCrypt)
    allow(secret).to receive(:passphrase?).and_wrap_original do |original, guess|
      next false if secret.passphrase.to_s.empty?
      begin
        ret = if secret.passphrase.to_s.start_with?('$argon2id$')
          Argon2::Password.verify_password(guess, secret.passphrase)
        else
          BCrypt::Password.new(secret.passphrase) == guess
        end
        secret.instance_variable_set(:@passphrase_temp, guess) if ret
        ret
      rescue BCrypt::Errors::InvalidHash, Argon2::ArgonHashFail
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

  # Factory method for Onetime::Metadata
  def create_stubbed_onetime_metadata(attributes = {})
    metadata = Onetime::Metadata.new

    # Default attributes
    # Note: Metadata uses objid/identifier (auto-generated), not 'key'
    # secret_identifier is the current field (secret_key is deprecated)
    default_attrs = {
      state: "new",
      secret_identifier: nil,
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
    allow(metadata).to receive(:secret_identifier!).and_return(true)
    allow(metadata).to receive(:state!).and_return(true)
    allow(metadata).to receive(:passphrase!).and_return(true)

    # Implement has_passphrase? behavior
    allow(metadata).to receive(:has_passphrase?).and_wrap_original do |original|
      !metadata.passphrase.to_s.empty?
    end

    metadata
  end

  # Creates a linked pair of Onetime::Secret and Onetime::Metadata
  def create_stubbed_onetime_secret_pair(attributes = {})
    # Extract and separate metadata and secret attributes
    metadata_attrs = {}
    secret_attrs = {}
    attributes.each do |key, value|
      metadata_attrs[key] = value
      secret_attrs[key] = value
    end

    # Create the objects first (identifiers are auto-generated)
    metadata = create_stubbed_onetime_metadata(metadata_attrs)
    secret = create_stubbed_onetime_secret(secret_attrs)

    # Now link them using their auto-generated identifiers
    metadata.instance_variable_set(:@secret_identifier, secret.identifier)
    secret.instance_variable_set(:@metadata_identifier, metadata.identifier)

    # Link them
    allow(secret).to receive(:load_metadata).and_return(metadata)

    [metadata, secret]
  end
end

RSpec.configure do |config|
  config.include ModelTestHelper
end
