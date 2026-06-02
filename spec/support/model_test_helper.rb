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

    default_attrs = {
      state: "new",
      passphrase: nil,
      passphrase_encryption: nil,
      custid: "test-customer-id",
    }

    merged_attrs = default_attrs.merge(attributes)
    merged_attrs.each do |attr, value|
      secret.instance_variable_set(:"@#{attr}", value)
    end

    allow(secret).to receive(:save).and_return(true)
    allow(secret).to receive(:exists?).and_return(true)
    allow(secret).to receive(:destroy!).and_return(true)

    allow(secret).to receive(:passphrase!).and_return(true)
    allow(secret).to receive(:passphrase_encryption!).and_return(true)
    allow(secret).to receive(:state!).and_return(true)

    allow(secret).to receive(:update_passphrase!).and_wrap_original do |original, val, **|
      secret.instance_variable_set(:@passphrase, Argon2::Password.create(val, t_cost: 1, m_cost: 5, p_cost: 1))
      secret.instance_variable_set(:@passphrase_encryption, '2')
      secret.instance_variable_set(:@passphrase_temp, val)
      true
    end

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
        false
      end
    end

    allow(secret).to receive(:has_passphrase?).and_wrap_original do |original|
      !secret.passphrase.to_s.empty?
    end

    secret
  end

  # Factory method for Onetime::Receipt
  def create_stubbed_receipt(attributes = {})
    receipt = Onetime::Receipt.new

    default_attrs = {
      state: "new",
      secret_identifier: nil,
      custid: "test-customer-id",
    }

    merged_attrs = default_attrs.merge(attributes)
    merged_attrs.each do |attr, value|
      receipt.instance_variable_set(:"@#{attr}", value)
    end

    allow(receipt).to receive(:save).and_return(true)
    allow(receipt).to receive(:exists?).and_return(true)
    allow(receipt).to receive(:destroy!).and_return(true)

    allow(receipt).to receive(:secret_identifier!).and_return(true)
    allow(receipt).to receive(:state!).and_return(true)

    receipt
  end

  # Creates a linked pair of Onetime::Secret and Onetime::Receipt
  def create_stubbed_secret_pair(attributes = {})
    receipt_attrs = {}
    secret_attrs = {}
    attributes.each do |key, value|
      receipt_attrs[key] = value
      secret_attrs[key] = value
    end

    receipt = create_stubbed_receipt(receipt_attrs)
    secret = create_stubbed_secret(secret_attrs)

    receipt.instance_variable_set(:@secret_identifier, secret.identifier)
    secret.instance_variable_set(:@receipt_identifier, receipt.identifier)

    allow(secret).to receive(:load_receipt).and_return(receipt)

    [receipt, secret]
  end

  # Aliases for v2 API specs
  alias create_stubbed_onetime_secret create_stubbed_secret
  alias create_stubbed_onetime_receipt create_stubbed_receipt
  alias create_stubbed_onetime_secret_pair create_stubbed_secret_pair
end

RSpec.configure do |config|
  config.include ModelTestHelper
end
