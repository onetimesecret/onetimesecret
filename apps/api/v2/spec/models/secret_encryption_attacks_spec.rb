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
      bcrypt_hash = BCrypt::Password.create(passphrase, cost: 12).to_s
      secret.instance_variable_set(:@passphrase, bcrypt_hash)
      secret.instance_variable_set(:@passphrase_encryption, '1')

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

    describe 'BCrypt (legacy)' do
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

end
