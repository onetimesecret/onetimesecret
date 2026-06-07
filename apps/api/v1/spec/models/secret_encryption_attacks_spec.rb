# apps/api/v1/spec/models/secret_encryption_attacks_spec.rb
#
# frozen_string_literal: true

require_relative '../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative File.join(Onetime::HOME, 'spec', 'support', 'model_test_helper.rb')

RSpec.describe Onetime::Secret, 'security hardening' do
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
      expect(avg_incorrect / avg_correct).to be_between(0.5, 2.0)
    end
  end

end
