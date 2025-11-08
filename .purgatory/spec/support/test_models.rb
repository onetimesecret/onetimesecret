# .purgatory/spec/support/test_models.rb
#
# frozen_string_literal: true

# Test double for Onetime::Secret that doesn't require Redis
class TestSecret
  attr_accessor :key, :passphrase_temp, :value, :value_encryption

  def initialize
    @key = nil
    @passphrase_temp = nil
    @value = nil
    @value_encryption = nil
  end

  def self.encryption_key(global_secret, key, passphrase)
    # Mimic the actual encryption key generation
    material = [global_secret, key, passphrase].compact.join(':')
    OpenSSL::Digest::SHA256.digest(material)
  end

  def encrypt_value(value, passphrase:)
    global_secret = OT.state[:global_secret]
    encryption_key = self.class.encryption_key(global_secret, @key, passphrase)
    @value = value.encrypt(key: encryption_key)
    @value_encryption = 2
  end

  def decrypted_value
    global_secret = OT.state[:global_secret]

    # Check if we should allow nil global secret
    if global_secret.nil? && OT.conf[:experimental][:allow_nil_global_secret]
      # Try fallback mechanism if mocked
      if respond_to?(:encryption_key_onetime_with_nil)
        encryption_key = encryption_key_onetime_with_nil
      else
        encryption_key = self.class.encryption_key(nil, @key, @passphrase_temp)
      end
    else
      encryption_key = self.class.encryption_key(global_secret, @key, @passphrase_temp)
    end

    @value.decrypt(key: encryption_key)
  end
end
