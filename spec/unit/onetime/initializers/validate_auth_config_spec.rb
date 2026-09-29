# spec/unit/onetime/initializers/validate_auth_config_spec.rb
#
# frozen_string_literal: true

# ValidateAuthConfig initializer — boot-time auth config enforcement.
#
# Focus: #validate_restrict_to_flags!
# (ADR-034#conflicting-auth-only-env-flags-are-a-boot-error, #4139). The config
# template renders full.restrict_to from four mutually exclusive AUTH_*_ONLY
# env vars and emits NOTHING when more than one is true, so the contradiction
# never reaches AuthConfig — it only exists in the process environment, and
# every reader downstream sees an unrestricted install. Conflicting flags are
# a fatal boot error naming each one.

require 'spec_helper'

RSpec.describe Onetime::Initializers::ValidateAuthConfig do
  subject(:initializer) { described_class.new }

  let(:only_flags) { described_class::RESTRICT_TO_ENV_FLAGS.keys }
  let(:auth_config) { instance_double(Onetime::AuthConfig, full_enabled?: full_mode) }
  let(:full_mode) { true }

  around do |example|
    flags = only_flags + ['SAML_ENABLED']
    saved = flags.to_h { |flag| [flag, ENV.fetch(flag, nil)] }
    flags.each { |flag| ENV.delete(flag) }
    example.run
    saved.each { |flag, value| value.nil? ? ENV.delete(flag) : ENV[flag] = value }
  end

  before do
    allow(Onetime).to receive(:auth_config).and_return(auth_config)
  end

  describe '#validate_restrict_to_flags!' do
    it 'returns [] when no flag is set' do
      expect(initializer.validate_restrict_to_flags!).to eq([])
    end

    it 'returns the single flag when exactly one is set' do
      described_class::RESTRICT_TO_ENV_FLAGS.each_key do |flag|
        only_flags.each { |other| ENV.delete(other) }
        ENV[flag] = 'true'

        expect(initializer.validate_restrict_to_flags!).to eq([flag])
      end
    end

    it 'ignores flags set to anything other than true' do
      ENV['AUTH_PASSWORD_ONLY'] = 'true'
      ENV['AUTH_SSO_ONLY']      = 'false'

      expect(initializer.validate_restrict_to_flags!).to eq(['AUTH_PASSWORD_ONLY'])
    end

    it 'raises when two flags are set, naming both and only those' do
      ENV['AUTH_PASSWORD_ONLY'] = 'true'
      ENV['AUTH_SSO_ONLY']      = 'true'

      expect { initializer.validate_restrict_to_flags! }
        .to raise_error(Onetime::ConfigError) { |error|
          expect(error.message).to include('AUTH_PASSWORD_ONLY=true')
          expect(error.message).to include('AUTH_SSO_ONLY=true')
          expect(error.message).not_to include('AUTH_WEBAUTHN_ONLY=true')
          expect(error.message).to include('2 AUTH_*_ONLY flags')
        }
    end

    it 'raises when all four flags are set, naming every one' do
      only_flags.each { |flag| ENV[flag] = 'true' }

      expect { initializer.validate_restrict_to_flags! }
        .to raise_error(Onetime::ConfigError) { |error|
          only_flags.each { |flag| expect(error.message).to include("#{flag}=true") }
          expect(error.message).to include('4 AUTH_*_ONLY flags')
        }
    end

    it 'names the method each offending flag would have selected' do
      ENV['AUTH_EMAIL_AUTH_ONLY'] = 'true'
      ENV['AUTH_WEBAUTHN_ONLY']   = 'true'

      expect { initializer.validate_restrict_to_flags! }
        .to raise_error(Onetime::ConfigError, /restrict_to: email_auth.*restrict_to: webauthn/m)
    end

    context 'in simple mode' do
      let(:full_mode) { false }

      it 'does not validate — restrict_to has no meaning there' do
        only_flags.each { |flag| ENV[flag] = 'true' }

        expect(initializer.validate_restrict_to_flags!).to eq([])
      end
    end
  end

  describe '#execute' do
    before do
      allow(auth_config).to receive_messages(configured?: true, validate_restrict_to!: nil)
    end

    it 'validates the flags before the rendered restriction' do
      ENV['AUTH_PASSWORD_ONLY'] = 'true'
      ENV['AUTH_SSO_ONLY']      = 'true'

      expect { initializer.execute(nil) }.to raise_error(Onetime::ConfigError, /AUTH_\*_ONLY/)
      expect(auth_config).not_to have_received(:validate_restrict_to!)
    end

    it 'proceeds to the rendered restriction when at most one flag is set' do
      ENV['AUTH_SSO_ONLY'] = 'true'

      initializer.execute(nil)

      expect(auth_config).to have_received(:validate_restrict_to!)
    end

    # SAML_ENABLED (#4604) is parsed here, by name, before anything reads it
    # per request (ADR-037: an unrecognized token fails boot, never resolves
    # to off). Every mode: the flag is inert in simple mode, but a typo is a
    # typo.
    describe 'the SAML_ENABLED switch' do
      it 'raises Onetime::ConfigError naming SAML_ENABLED on an unrecognized token, before the restriction checks' do
        ENV['SAML_ENABLED'] = 'ture'

        expect { initializer.execute(nil) }.to raise_error(Onetime::ConfigError) { |error|
          expect(error.message).to include('SAML_ENABLED')
          expect(error.message).not_to include('ture')
        }
        expect(auth_config).not_to have_received(:validate_restrict_to!)
      end

      context 'in simple mode' do
        let(:full_mode) { false }

        it 'still raises on an unrecognized token' do
          ENV['SAML_ENABLED'] = 'enabled'

          expect { initializer.execute(nil) }.to raise_error(Onetime::ConfigError, /SAML_ENABLED/)
        end
      end

      [nil, '', 'false', 'true', 'yes', '0'].each do |value|
        it "proceeds when SAML_ENABLED is #{value.inspect}" do
          value.nil? ? ENV.delete('SAML_ENABLED') : ENV['SAML_ENABLED'] = value

          expect { initializer.execute(nil) }.not_to raise_error
          expect(auth_config).to have_received(:validate_restrict_to!)
        end
      end

      it 'returns the parsed value from #validate_saml_enabled_flag!' do
        ENV['SAML_ENABLED'] = 'on'
        expect(initializer.validate_saml_enabled_flag!).to be(true)
        ENV.delete('SAML_ENABLED')
        expect(initializer.validate_saml_enabled_flag!).to be(false)
      end
    end
  end
end
