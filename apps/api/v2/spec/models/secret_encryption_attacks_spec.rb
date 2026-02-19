# apps/api/v2/spec/models/secret_encryption_attacks_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')

RSpec.describe Onetime::Secret, 'security hardening' do
  let(:secret) { create_stubbed_onetime_secret(key: 'test-secret-key-12345') }
  let(:passphrase) { 'secure-test-passphrase' }
  let(:secret_value) { 'Sensitive information 123' }

  before do
    allow(OT).to receive_messages(global_secret: 'global-test-secret', conf: {
      'development' => {
        'allow_nil_global_secret' => false,
      },
    }
    )
  end

  describe 'timing attack resistance', allow_redis: false do
    before do
      # Set up a secret with known passphrase
      secret.update_passphrase!(passphrase)
      # Clear the temp passphrase after setup
      secret.instance_variable_set(:@passphrase_temp, nil)
    end

    it 'uses Argon2 for secure comparison by default' do
      # Argon2::Password.verify_password provides constant-time comparison
      # This is what provides the timing attack resistance
      # Default passphrase encryption uses Argon2 (mode '2')
      expect(secret.passphrase_encryption).to eq('2')

      # Verify actual Argon2 comparison works
      expect(secret.passphrase?(passphrase)).to be true
      expect(secret.passphrase?('wrong-passphrase')).to be false
    end

    it 'falls back to BCrypt for legacy hashes' do
      # Set up a BCrypt hash directly (simulating legacy data)
      bcrypt_hash = BCrypt::Password.create(passphrase, cost: 12).to_s
      secret.instance_variable_set(:@passphrase, bcrypt_hash)
      secret.instance_variable_set(:@passphrase_encryption, '1')

      # Verify actual BCrypt comparison works
      expect(secret.passphrase?(passphrase)).to be true
      expect(secret.passphrase?('wrong-passphrase')).to be false
    end

    it 'takes similar time for correct and incorrect passphrases' do
      # This test ensures that comparing correct and incorrect passphrases
      # takes approximately the same time, which is a hallmark of constant-time
      # comparison algorithms that resist timing attacks

      # Skip in CI environment where timing can be unreliable
      skip 'Timing tests may be unreliable in CI environments' if ENV['CI']

      # Warm up
      5.times { secret.passphrase?(passphrase) }
      5.times { secret.passphrase?('wrong-passphrase') }

      # Measure correct passphrase
      correct_times = []
      10.times do
        start_time = Onetime.now_in_μs
        secret.passphrase?(passphrase)
        end_time   = Onetime.now_in_μs
        correct_times << (end_time - start_time)
      end

      # Measure incorrect passphrase
      incorrect_times = []
      10.times do
        start_time = Onetime.now_in_μs
        secret.passphrase?('wrong-passphrase')
        end_time   = Onetime.now_in_μs
        incorrect_times << (end_time - start_time)
      end

      # Calculate averages (use float division for accurate timing)
      avg_correct   = correct_times.sum.to_f / correct_times.size
      avg_incorrect = incorrect_times.sum.to_f / incorrect_times.size

      # Skip if times are too small to measure reliably (< 100μs)
      skip 'Execution too fast to measure reliably' if avg_correct < 100 || avg_incorrect < 100

      # Timing difference should be minimal
      # Allow up to 2x difference because BCrypt comparison exits early on
      # hash algorithm mismatch, but actual password comparison is constant time
      expect(avg_incorrect / avg_correct).to be_between(0.5, 2.0)
    end
  end

  describe 'passphrase verification across algorithms', allow_redis: false do
    # Test passphrases covering various character types and lengths
    # Defined as constant to be accessible at describe/context level
    TEST_PASSPHRASES = {
      'simple ASCII' => 'test-passphrase-123',
      'with spaces' => 'my secret passphrase',
      'unicode characters' => 'пароль-密码-🔐',
      'special characters' => '!@#$%^&*()_+-=[]{}|;:,.<>?',
      'very long' => 'a' * 256,
      'minimum length' => 'abc',
    }.freeze

    shared_examples 'correct passphrase verification' do |algorithm_name, encryption_mode|
      TEST_PASSPHRASES.each do |description, phrase|
        context "with #{description} passphrase" do
          let(:test_phrase) { phrase }

          before do
            case encryption_mode
            when '2' # Argon2
              secret.update_passphrase!(test_phrase)
              secret.instance_variable_set(:@passphrase_temp, nil)
            when '1' # BCrypt
              bcrypt_hash = BCrypt::Password.create(test_phrase, cost: 4).to_s
              secret.instance_variable_set(:@passphrase, bcrypt_hash)
              secret.instance_variable_set(:@passphrase_encryption, '1')
            end
          end

          it "returns true for correct passphrase (#{algorithm_name})" do
            expect(secret.passphrase?(test_phrase)).to be true
          end

          it "returns false for incorrect passphrase (#{algorithm_name})" do
            expect(secret.passphrase?('definitely-wrong')).to be false
          end

          it "is case-sensitive (#{algorithm_name})" do
            skip 'No letters to test case sensitivity' unless test_phrase.match?(/[a-zA-Z]/)
            expect(secret.passphrase?(test_phrase.swapcase)).to be false
          end
        end
      end
    end

    describe 'Argon2 (current default)' do
      include_examples 'correct passphrase verification', 'Argon2', '2'
    end

    describe 'BCrypt (legacy fallback)' do
      include_examples 'correct passphrase verification', 'BCrypt', '1'
    end

    describe 'edge cases' do
      it 'returns false when no passphrase is set' do
        expect(secret.passphrase).to be_nil
        expect(secret.passphrase?('any-passphrase')).to be false
      end

      it 'returns false for empty string when passphrase exists' do
        secret.update_passphrase!('real-passphrase')
        secret.instance_variable_set(:@passphrase_temp, nil)
        expect(secret.passphrase?('')).to be false
      end

      it 'returns false for nil when passphrase exists' do
        secret.update_passphrase!('real-passphrase')
        secret.instance_variable_set(:@passphrase_temp, nil)
        expect(secret.passphrase?(nil)).to be false
      end

      it 'handles whitespace-only passphrases correctly' do
        whitespace_pass = '   '
        secret.update_passphrase!(whitespace_pass)
        secret.instance_variable_set(:@passphrase_temp, nil)

        expect(secret.passphrase?(whitespace_pass)).to be true
        expect(secret.passphrase?('   ')).to be true  # Same whitespace
        expect(secret.passphrase?('  ')).to be false  # Different length
      end
    end
  end

  describe 'handling corrupted encryption data', allow_redis: false do
    # Longer plaintext that spans multiple AES blocks for IV/block corruption tests
    let(:long_secret_value) { 'This is a longer secret value that spans multiple AES blocks for testing' }

    before do
      secret.encrypt_value(secret_value)
    end

    it 'raises an error when encrypted value is truncated' do
      # Corrupt the encrypted value by truncating bytes. AES-CBC uses 16-byte blocks
      # with PKCS7 padding. Truncating 5 bytes ensures incorrect block length which
      # reliably triggers CipherError across OpenSSL versions.
      secret.value = secret.value[0..-6]

      expect { secret.decrypted_value }.to raise_error(OpenSSL::Cipher::CipherError)
    end

    it 'detects byte-level corruption in encrypted values' do
      original_encrypted = secret.value.dup

      # XOR-flip bytes at strategic positions (start, middle, end) to ensure
      # corruption regardless of ciphertext block boundaries or specific byte positions.
      # This tests the security property: corrupted ciphertext must not
      # decrypt to the original plaintext.
      corrupted = original_encrypted.bytes.map.with_index do |byte, i|
        i % 8 == 0 ? byte ^ 0xFF : byte
      end.pack('C*')
      secret.value = corrupted

      decrypted = begin
        secret.decrypted_value
      rescue OpenSSL::Cipher::CipherError
        nil # Error is acceptable - corruption was detected
      end

      # Security property: corrupted ciphertext must not produce original plaintext
      expect(decrypted).not_to eq(secret_value),
        'Corrupted ciphertext should not decrypt to original plaintext'
    end

    it 'produces corrupted plaintext when IV is corrupted (first 16 bytes)' do
      # In AES-CBC, the IV affects only the first block of plaintext.
      # Corrupting the IV should NOT raise an error but SHOULD produce
      # incorrect plaintext. This tests the security property that IV
      # tampering is detectable only by content verification, not crypto errors.

      secret.encrypt_value(long_secret_value)
      original_encrypted = secret.value.dup

      # The encrypted value is raw binary, not Base64 encoded
      # Skip if ciphertext is too short (need at least IV + 1 block = 32 bytes)
      skip 'Ciphertext too short for IV corruption test' if original_encrypted.bytesize < 32

      # Flip bits in the IV (first 16 bytes only)
      corrupted_iv = original_encrypted[0, 16].bytes.map { |b| b ^ 0xFF }.pack('C*')
      corrupted = corrupted_iv + original_encrypted[16..]
      secret.value = corrupted

      # IV corruption in CBC mode does not cause CipherError - it silently
      # corrupts the first plaintext block while remaining blocks decrypt fine
      decrypted = secret.decrypted_value

      expect(decrypted).not_to eq(long_secret_value),
        'IV-corrupted ciphertext must not decrypt to original plaintext'
      # CBC mode property: IV corruption affects decryption but may not raise errors.
      # The key security property is that the original plaintext is NOT recovered.
      # Note: The encryptor gem's IV handling means we can't make strong assertions
      # about which bytes are corrupted, only that corruption is detectable.
      expect(decrypted.length).to be > 0
    end

    it 'raises error when exactly one AES block is truncated' do
      # Remove exactly 16 bytes (one AES block) from the end.
      # This tests that the PKCS7 padding validation fails correctly
      # when a complete block is removed.

      secret.encrypt_value(long_secret_value)

      # The encrypted value is raw binary, not Base64 encoded
      # Skip if ciphertext is too short
      skip 'Ciphertext too short for block truncation test' if secret.value.bytesize < 32

      truncated = secret.value[0...-16]
      secret.value = truncated

      expect { secret.decrypted_value }.to raise_error(OpenSSL::Cipher::CipherError)
    end

    it 'raises error when ciphertext has non-block-aligned length' do
      # AES requires ciphertext length to be multiple of 16 bytes.
      # Remove 7 bytes to create invalid block alignment.

      # The encrypted value is raw binary, not Base64 encoded
      # Skip if ciphertext is too short
      skip 'Ciphertext too short for alignment test' if secret.value.bytesize < 16

      misaligned = secret.value[0...-7]
      secret.value = misaligned

      expect { secret.decrypted_value }.to raise_error(OpenSSL::Cipher::CipherError)
    end

    it 'handles corruption edge cases gracefully' do
      # Test with various forms of corruption

      # Case 1: Empty value
      secret.value = ''
      # Empty value with encryption mode 2 can trigger different errors depending on
      # the environment (OpenSSL, frozen string handling, etc.)
      expect { secret.decrypted_value }.to(raise_error do |error|
        expect([OpenSSL::Cipher::CipherError, ArgumentError, FrozenError]).to include(error.class)
      end,
                                          )

      # Case 2: Nil value
      secret.value = nil
      expect { secret.decrypted_value }.to raise_error(NoMethodError)

      # Case 3: Invalid encryption mode
      secret.value            = secret_value
      secret.value_encryption = 99
      expect { secret.decrypted_value }.to raise_error(RuntimeError, /Unknown encryption mode/)

      # Case 4: Non-encrypted binary data
      secret.value            = "\x00\x01\x02\x03"
      secret.value_encryption = 2
      expect { secret.decrypted_value }.to raise_error(OpenSSL::Cipher::CipherError)
    end

    it 'fails predictably with mismatched encryption modes' do
      # Encrypt with v2
      secret.value_encryption = 2
      secret.encrypt_value(secret_value)
      encrypted_value         = secret.value.dup

      # Try to decrypt with v1
      secret.value_encryption = 1
      expect { secret.decrypted_value }.to raise_error(OpenSSL::Cipher::CipherError)

      # Try to decrypt with no encryption
      secret.value            = encrypted_value
      secret.value_encryption = 0
      expect { secret.decrypted_value }.not_to raise_error
      expect(secret.decrypted_value).not_to eq(secret_value)
    end
  end

  describe 'key generation security', allow_redis: false do
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

      # Change secret identifier
      allow(secret).to receive(:identifier).and_return('test-secret-identifier-12346') # Changed last digit
      modified_key1 = secret.encryption_key_v2

      # Change global secret slightly
      allow(secret).to receive(:identifier).and_return('test-secret-identifier-12345') # Original
      allow(OT).to receive(:global_secret).and_return('global-test-secret-')
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
