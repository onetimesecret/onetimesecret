# support/enckey_test.rb
#
# Test script for debugging OnetimeSecret encryption keys
# This utility helps diagnose encryption/decryption issues by testing
# various key combinations and encryption methods.

$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))

require 'onetime'
require 'v2/secret'

Onetime.boot! :app

# Helper method to test decryption with different parameters
def test_decrypt(encrypted_value, secret_identifier, encryption_mode, passphrase=nil, global_secrets=[])
  puts "Testing with mode: #{encryption_mode}, passphrase: #{passphrase ? 'YES' : 'NO'}"

  # Create a temporary secret object
  secret = Onetime::Secret.new
  secret.identifier = secret_identifier
  secret.value = encrypted_value
  secret.value_encryption = encryption_mode
  secret.passphrase_temp = passphrase if passphrase

  # For each potential global secret
  global_secrets.each do |global_secret|
    begin
      # Temporarily override global secret
      original_secret =  OT.conf['site']['secret']
      # NOTE: As of v0.23.0 there is no OT.global_secret. Need to find another
      # way of modifying the value used. Try passing it in as an override. For
      # the upcoming v3 style, let's keep that in mind.
      OT.instance_variable_set(:@global_secret, global_secret)

      # Try decryption
      decrypted = secret.decrypted_value
      puts "✅ SUCCESS with global_secret: #{global_secret.inspect}"
      puts "Decrypted value: #{decrypted.inspect}"
      return decrypted
    rescue OpenSSL::Cipher::CipherError => e
      puts "❌ FAILED with global_secret: #{global_secret.inspect} (#{e.message})"
    ensure
      # Restore original global secret
      OT.instance_variable_set(:@global_secret, original_secret)
    end
  end

  # Try manual key generation methods
  puts "\nTrying manual key generation methods:"

  global_secrets.each do |global_secret|
    # Try v1 style encryption key
    v1_key = Onetime::Secret.encryption_key(secret_identifier, passphrase)
    try_manual_decrypt(encrypted_value, v1_key, "V1 style (key + passphrase)")

    # Try v2 style encryption key
    v2_key = Onetime::Secret.encryption_key(global_secret, secret_identifier, passphrase)
    try_manual_decrypt(encrypted_value, v2_key, "V2 style (global + key + passphrase)")

    # Try nil global secret
    v2_nil_key = Onetime::Secret.encryption_key(nil, secret_identifier, passphrase)
    try_manual_decrypt(encrypted_value, v2_nil_key, "V2 style with nil global")
  end

  return nil
end

# Helper to try manual decryption with a specific key
def try_manual_decrypt(encrypted_value, key, method_name)
  begin
    decrypted = encrypted_value.decrypt(key: key)
    puts "✅ SUCCESS with #{method_name}"
    puts "Decrypted value: #{decrypted.inspect}"
    puts "Key used: #{key.inspect}"
    return decrypted
  rescue OpenSSL::Cipher::CipherError => e
    puts "❌ FAILED with #{method_name} (#{e.message})"
    return nil
  end
end

# Function to find a problematic secret and test it
def test_problematic_secret(secret_identifier, additional_global_secrets=[], potential_passphrases=nil)
  secret = Onetime::Secret.load(secret_identifier)
  potential_passphrases ||= [nil, ""]  # Add potential passphrases if applicable

  if secret.nil?
    puts "Secret not found with key: #{secret_identifier}"
    return
  end

  puts "Found secret with key: #{secret_identifier}"
  puts "Encryption mode: #{secret.value_encryption}"
  puts "Has passphrase: #{secret.has_passphrase?}"

  # List of potential global secrets to try
  potential_global_secrets = [
    OT.conf['site']['secret'],  # Current global secret
    nil,               # No global secret
    # Add other potential global secrets that might have been used
    "old_global_secret_value",
    "", # Empty string
    "CHANGEME",
  ].concat(additional_global_secrets).flatten

  # Try decryption with different parameter combinations
  encrypted_value = secret.value

  result = nil
  potential_passphrases.each do |passphrase|
    result = test_decrypt(encrypted_value, secret_identifier, secret.value_encryption,
                         passphrase, potential_global_secrets)
    break if result
  end

  if result
    puts "\nSUCCESS! Found working configuration."
  else
    puts "\nFailed to decrypt with all tried combinations."
  end
end

# Function to manually test encryption key generation with specific parameters
def test_encryption_key_generation(secret_identifier, passphrase=nil, global_secrets=[])
  puts "Testing encryption key generation for secret_identifier: #{secret_identifier}"

  global_secrets.each do |global_secret|
    # V1 style (no global secret)
    v1_key = Onetime::Secret.encryption_key(secret_identifier, passphrase)
    puts "V1 style key (key + passphrase): #{v1_key}"

    # V2 style (with global secret)
    v2_key = Onetime::Secret.encryption_key(global_secret, secret_identifier, passphrase)
    puts "V2 style key (global + key + passphrase) with global=#{global_secret.inspect}: #{v2_key}"
  end
end

# Create a test value and encrypt it with different methods for comparison
def create_test_encryptions(test_value, secret_identifier, passphrase=nil, global_secrets=[])
  puts "Creating test encryptions for value: #{test_value.inspect}"

  encryptions = {}

  global_secrets.each do |global_secret|
    # V1 style encryption
    v1_key = Onetime::Secret.encryption_key(secret_identifier, passphrase)
    v1_encrypted = test_value.encrypt(key: v1_key)
    encryptions["v1_#{global_secret.inspect}"] = v1_encrypted
    puts "V1 style encryption: #{v1_encrypted.inspect}"

    # V2 style encryption
    v2_key = Onetime::Secret.encryption_key(global_secret, secret_identifier, passphrase)
    v2_encrypted = test_value.encrypt(key: v2_key)
    encryptions["v2_#{global_secret.inspect}"] = v2_encrypted
    puts "V2 style encryption with global=#{global_secret.inspect}: #{v2_encrypted.inspect}"
  end

  return encryptions
end

# === USAGE EXAMPLES ===

# 1. Test a problematic secret with a known key:
#
# test_problematic_secret("abc123secretkey")
#
# This will attempt to decrypt the secret using various global secrets and passphrase combinations

# 2. Test a secret with custom potential global secrets:
#
# test_problematic_secret(
#   "abc123secretkey",
#   ["old_production_secret", "deployment_secret"]
# )

# 3. Test a secret with custom global secrets and passphrases:
#
# test_problematic_secret(
#   "abc123secretkey",
#   ["old_production_secret"],
#   ["userpassword", "custompass123"]
# )

# 4. Test how encryption keys are generated with different parameters:
#
# test_encryption_key_generation(
#   "abc123secretkey",
#   "optional_passphrase",
#   [ OT.conf['site']['secret'], "old_global_secret"]
# )

# 5. Create test encryptions to compare different encryption methods:
#
# create_test_encryptions(
#   "This is my secret message",
#   "abc123secretkey",
#   "optional_passphrase",
#   [ OT.conf['site']['secret'], nil]
# )
