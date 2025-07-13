# tests/unit/ruby/rspec/apps/api/v2/models/secret_encryption_attacks_spec.rb

require_relative '../../../../spec_helper'

RSpec.describe V1::Secret, 'security hardening' do
  let(:secret) { create_stubbed_secret(key: "test-secret-key-12345") }
  let(:passphrase) { "secure-test-passphrase" }
  let(:secret_value) { "Sensitive information 123" }

  before do
    allow(OT).to receive(:global_secret).and_return("global-test-secret")
  end

  describe 'timing attack resistance' do
    before do
      # Set up a secret with known passphrase
      secret.update_passphrase!(passphrase)
      # Clear the temp passphrase after setup
      secret.instance_variable_set(:@passphrase_temp, nil)
    end

    it 'uses BCrypt for secure comparison' do
      # BCrypt::Password instance receives == method for comparison
      # This is what provides the timing attack resistance
      bcrypt_password = instance_double(BCrypt::Password)
      expect(BCrypt::Password).to receive(:new).with(secret.passphrase).and_return(bcrypt_password)
      expect(bcrypt_password).to receive(:==).with(passphrase).and_return(true)

      secret.passphrase?(passphrase)
    end

    it 'takes similar time for correct and incorrect passphrases' do
      # Skip in CI environment where timing can be unreliable
      skip "Timing tests may be unreliable in CI environments" if ENV['CI']

      # Rest of the test remains the same...
      # Warm up
      5.times { secret.passphrase?(passphrase) }
      5.times { secret.passphrase?("wrong-passphrase") }

      # Measure correct passphrase
      correct_times = []
      10.times do
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        secret.passphrase?(passphrase)
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        correct_times << (end_time - start_time)
      end

      # Measure incorrect passphrase
      incorrect_times = []
      10.times do
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        secret.passphrase?("wrong-passphrase")
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        incorrect_times << (end_time - start_time)
      end

      # Calculate averages
      avg_correct = correct_times.sum / correct_times.size
      avg_incorrect = incorrect_times.sum / incorrect_times.size

      # Timing difference should be minimal
      expect(avg_incorrect / avg_correct).to be_between(0.5, 2.0)
    end
  end

  describe 'handling corrupted encryption data' do
    before do
      secret.encrypt_value(secret_value)
    end

    it 'raises an error when encrypted value is corrupted' do
      # Corrupt the encrypted value
      secret.value = secret.value[0..-2] + "X"

      expect { secret.decrypted_value }.to raise_error(OpenSSL::Cipher::CipherError)
    end

    it 'handles corruption edge cases gracefully' do
      # Test with various forms of corruption

      # Case 1: Empty value
      secret.value = ""
      # Ruby 3.1 raises ArgumentError, 3.2+ raises OpenSSL::Cipher::CipherError
      # We accept either behavior for the v1 legacy code
      expect { secret.decrypted_value }.to raise_error { |error|
        expect([ArgumentError, OpenSSL::Cipher::CipherError]).to include(error.class)
      }

      # Case 2: Nil value
      secret.value = nil
      expect { secret.decrypted_value }.to raise_error(NoMethodError)

      # Case 3: Invalid encryption mode
      secret.value = secret_value
      secret.value_encryption = 99
      expect { secret.decrypted_value }.to raise_error(RuntimeError, /Unknown encryption mode/)

      # Case 4: Non-encrypted binary data
      secret.value = "\x00\x01\x02\x03"
      secret.value_encryption = 2
      expect { secret.decrypted_value }.to raise_error(OpenSSL::Cipher::CipherError)
    end

    it 'fails predictably with mismatched encryption modes' do
      # Encrypt with v2
      secret.value_encryption = 2
      secret.encrypt_value(secret_value)
      encrypted_value = secret.value.dup

      # Try to decrypt with v1
      secret.value_encryption = 1
      expect { secret.decrypted_value }.to raise_error(OpenSSL::Cipher::CipherError)

      # Try to decrypt with no encryption
      secret.value = encrypted_value
      secret.value_encryption = 0
      expect { secret.decrypted_value }.not_to raise_error
      expect(secret.decrypted_value).not_to eq(secret_value)
    end
  end

  describe 'key generation security' do
    it 'produces secure-length encryption keys' do
      key1 = secret.encryption_key_v1
      key2 = secret.encryption_key_v2

      # SHA256 produces 64-character hex strings
      expect(key1.length).to eq(64)
      expect(key2.length).to eq(64)
    end

    it 'generates different keys when inputs change slightly' do
      # Original key
      orig_key = secret.encryption_key_v2

      # Change secret key
      allow(secret).to receive(:key).and_return("test-secret-key-12346") # Changed last digit
      modified_key1 = secret.encryption_key_v2

      # Change global secret slightly
      allow(secret).to receive(:key).and_return("test-secret-key-12345") # Original
      allow(OT).to receive(:global_secret).and_return("global-test-secret-")
      modified_key2 = secret.encryption_key_v2

      # Keys should be completely different
      expect(orig_key).not_to eq(modified_key1)
      expect(orig_key).not_to eq(modified_key2)
      expect(modified_key1).not_to eq(modified_key2)

      # Keys should not have significant character overlap
      # Count matching characters at same positions
      matches1 = orig_key.chars.zip(modified_key1.chars).count { |a, b| a == b }
      matches2 = orig_key.chars.zip(modified_key2.chars).count { |a, b| a == b }

      # A secure hash function should have minimal matches (ideally around 25% by chance)
      expect(matches1.to_f / orig_key.length).to be < 0.35
      expect(matches2.to_f / orig_key.length).to be < 0.35
    end
  end
end
