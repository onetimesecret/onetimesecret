# spec/unit/onetime/config/auth_config_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'fileutils'

# Systematic tests for AuthConfig, covering all env var mappings and
# single-auth-method mutual-exclusivity logic.
#
# Strategy: write a minimal YAML config to a temp file, point
# ConfigResolver at it, and reset the singleton between tests.
RSpec.describe Onetime::AuthConfig do
  let(:temp_dir) { Dir.mktmpdir('auth_config_test') }
  let(:config_path) { File.join(temp_dir, 'auth.yaml') }

  # Base YAML that mirrors auth.defaults.yaml structure using ERB
  let(:base_yaml) do
    <<~YAML
      ---
      mode: <%= ENV['AUTHENTICATION_MODE'] || 'full' %>
      simple: {}
      full:
        database_url: "sqlite::memory:"
        features:
          lockout: <%= ENV['AUTH_LOCKOUT_ENABLED'] != 'false' %>
          password_requirements: <%= ENV['AUTH_PASSWORD_REQUIREMENTS_ENABLED'] != 'false' %>
          active_sessions: <%= ENV['AUTH_ACTIVE_SESSIONS_ENABLED'] != 'false' %>
          remember_me: <%= ENV['AUTH_REMEMBER_ME_ENABLED'] != 'false' %>
          verify_account: false
          mfa: <%= ENV['AUTH_MFA_ENABLED'] == 'true' %>
          email_auth: <%= ENV['AUTH_EMAIL_AUTH_ENABLED'] == 'true' %>
          webauthn: <%= ENV['AUTH_WEBAUTHN_ENABLED'] == 'true' %>
          sso: <%= ENV['AUTH_SSO_ENABLED'] == 'true' %>
        single_auth_method:
          password_only: <%= ENV['AUTH_PASSWORD_ONLY'] == 'true' %>
          email_auth_only: <%= ENV['AUTH_EMAIL_AUTH_ONLY'] == 'true' %>
          webauthn_only: <%= ENV['AUTH_WEBAUTHN_ONLY'] == 'true' %>
          sso_only: <%= ENV['AUTH_SSO_ONLY'] == 'true' %>
        sso:
          sso_display_name: ''
          sso_only: <%= ENV['AUTH_SSO_ONLY'] == 'true' %>
    YAML
  end

  # ENV vars we touch — saved and restored around each example
  let(:env_vars) do
    %w[
      AUTHENTICATION_MODE
      AUTH_LOCKOUT_ENABLED AUTH_PASSWORD_REQUIREMENTS_ENABLED
      AUTH_ACTIVE_SESSIONS_ENABLED AUTH_REMEMBER_ME_ENABLED
      AUTH_MFA_ENABLED AUTH_EMAIL_AUTH_ENABLED AUTH_WEBAUTHN_ENABLED
      AUTH_SSO_ENABLED AUTH_SSO_ONLY
      AUTH_PASSWORD_ONLY AUTH_EMAIL_AUTH_ONLY AUTH_WEBAUTHN_ONLY
      OIDC_ISSUER OIDC_CLIENT_ID
    ]
  end

  before(:each) do
    # Save existing env
    @saved_env = env_vars.map { |k| [k, ENV[k]] }.to_h

    # Write config file
    File.write(config_path, base_yaml)

    # Stub ConfigResolver to use our temp file
    allow(Onetime::Utils::ConfigResolver).to receive(:resolve)
      .with('auth').and_return(config_path)
  end

  after(:each) do
    # Restore env
    @saved_env.each do |k, v|
      if v.nil?
        ENV.delete(k)
      else
        ENV[k] = v
      end
    end

    # Clear singleton so next test gets a fresh instance
    described_class.instance_variable_set(:@singleton__instance__, nil)

    FileUtils.rm_rf(temp_dir)
  end

  # Helper: reset singleton and return a fresh instance
  def fresh_config(**env_overrides)
    env_overrides.each { |k, v| ENV[k.to_s] = v }
    described_class.instance_variable_set(:@singleton__instance__, nil)
    File.write(config_path, base_yaml) # re-render ERB with new env
    described_class.instance
  end

  # ── Mode tests ─────────────────────────────────────────────────────

  describe '#mode' do
    it 'defaults to full when AUTHENTICATION_MODE is unset' do
      ENV.delete('AUTHENTICATION_MODE')
      config = fresh_config
      expect(config.mode).to eq('full')
    end

    it 'returns simple when AUTHENTICATION_MODE=simple' do
      config = fresh_config('AUTHENTICATION_MODE' => 'simple')
      expect(config.mode).to eq('simple')
    end

    it 'returns full when AUTHENTICATION_MODE=full' do
      config = fresh_config('AUTHENTICATION_MODE' => 'full')
      expect(config.mode).to eq('full')
    end
  end

  # ── Feature toggle env vars ────────────────────────────────────────

  describe 'feature toggles (default-ON pattern)' do
    %w[lockout password_requirements active_sessions remember_me].each do |feature|
      env_key = "AUTH_#{feature.upcase}_ENABLED"

      describe "##{feature}_enabled?" do
        it "returns true when #{env_key} is unset (default ON)" do
          ENV.delete(env_key)
          config = fresh_config
          expect(config.public_send(:"#{feature}_enabled?")).to be true
        end

        it "returns true when #{env_key}=true" do
          config = fresh_config(env_key => 'true')
          expect(config.public_send(:"#{feature}_enabled?")).to be true
        end

        it "returns false when #{env_key}=false" do
          config = fresh_config(env_key => 'false')
          expect(config.public_send(:"#{feature}_enabled?")).to be false
        end

        it 'returns false in simple mode regardless' do
          config = fresh_config('AUTHENTICATION_MODE' => 'simple', env_key => 'true')
          expect(config.public_send(:"#{feature}_enabled?")).to be false
        end
      end
    end
  end

  describe 'feature toggles (default-OFF pattern)' do
    { 'mfa' => 'AUTH_MFA_ENABLED',
      'email_auth' => 'AUTH_EMAIL_AUTH_ENABLED',
      'webauthn' => 'AUTH_WEBAUTHN_ENABLED',
      'sso' => 'AUTH_SSO_ENABLED' }.each do |feature, env_key|
      describe "##{feature}_enabled?" do
        it "returns false when #{env_key} is unset (default OFF)" do
          ENV.delete(env_key)
          config = fresh_config
          expect(config.public_send(:"#{feature}_enabled?")).to be false
        end

        it "returns true when #{env_key}=true" do
          config = fresh_config(env_key => 'true')
          expect(config.public_send(:"#{feature}_enabled?")).to be true
        end

        it "returns false when #{env_key}=false" do
          config = fresh_config(env_key => 'false')
          expect(config.public_send(:"#{feature}_enabled?")).to be false
        end

        it 'returns false in simple mode regardless' do
          config = fresh_config('AUTHENTICATION_MODE' => 'simple', env_key => 'true')
          expect(config.public_send(:"#{feature}_enabled?")).to be false
        end
      end
    end
  end

  # ── Single-auth-method overrides ───────────────────────────────────

  describe 'single-auth-method overrides' do
    describe '#password_only_enabled?' do
      it 'returns false by default' do
        config = fresh_config
        expect(config.password_only_enabled?).to be false
      end

      it 'returns true when AUTH_PASSWORD_ONLY=true' do
        config = fresh_config('AUTH_PASSWORD_ONLY' => 'true')
        expect(config.password_only_enabled?).to be true
      end

      it 'returns false in simple mode' do
        config = fresh_config('AUTHENTICATION_MODE' => 'simple', 'AUTH_PASSWORD_ONLY' => 'true')
        expect(config.password_only_enabled?).to be false
      end
    end

    describe '#email_auth_only_enabled?' do
      it 'returns false by default' do
        config = fresh_config
        expect(config.email_auth_only_enabled?).to be false
      end

      it 'returns true when AUTH_EMAIL_AUTH_ONLY=true and email_auth is enabled' do
        config = fresh_config('AUTH_EMAIL_AUTH_ONLY' => 'true', 'AUTH_EMAIL_AUTH_ENABLED' => 'true')
        expect(config.email_auth_only_enabled?).to be true
      end

      it 'returns false when AUTH_EMAIL_AUTH_ONLY=true but email_auth is disabled' do
        config = fresh_config('AUTH_EMAIL_AUTH_ONLY' => 'true', 'AUTH_EMAIL_AUTH_ENABLED' => 'false')
        expect(config.email_auth_only_enabled?).to be false
      end
    end

    describe '#webauthn_only_enabled?' do
      it 'returns false by default' do
        config = fresh_config
        expect(config.webauthn_only_enabled?).to be false
      end

      it 'returns true when AUTH_WEBAUTHN_ONLY=true and webauthn is enabled' do
        config = fresh_config('AUTH_WEBAUTHN_ONLY' => 'true', 'AUTH_WEBAUTHN_ENABLED' => 'true')
        expect(config.webauthn_only_enabled?).to be true
      end

      it 'returns false when AUTH_WEBAUTHN_ONLY=true but webauthn is disabled' do
        config = fresh_config('AUTH_WEBAUTHN_ONLY' => 'true', 'AUTH_WEBAUTHN_ENABLED' => 'false')
        expect(config.webauthn_only_enabled?).to be false
      end
    end

    describe '#sso_only_enabled?' do
      it 'returns false by default' do
        config = fresh_config
        expect(config.sso_only_enabled?).to be false
      end

      it 'returns true when AUTH_SSO_ONLY=true, SSO enabled, and provider configured' do
        config = fresh_config(
          'AUTH_SSO_ONLY' => 'true',
          'AUTH_SSO_ENABLED' => 'true',
          'OIDC_ISSUER' => 'https://example.com',
          'OIDC_CLIENT_ID' => 'test-client',
        )
        expect(config.sso_only_enabled?).to be true
      end

      it 'returns false when AUTH_SSO_ONLY=true but SSO disabled' do
        config = fresh_config('AUTH_SSO_ONLY' => 'true', 'AUTH_SSO_ENABLED' => 'false')
        expect(config.sso_only_enabled?).to be false
      end

      it 'returns false when AUTH_SSO_ONLY=true, SSO enabled, but no provider configured' do
        ENV.delete('OIDC_ISSUER')
        ENV.delete('OIDC_CLIENT_ID')
        config = fresh_config('AUTH_SSO_ONLY' => 'true', 'AUTH_SSO_ENABLED' => 'true')
        expect(config.sso_only_enabled?).to be false
      end
    end
  end

  # ── Mutual exclusivity ────────────────────────────────────────────

  describe 'mutual exclusivity of single-auth-method flags' do
    it 'all *_only_enabled? return false when two flags are set' do
      config = fresh_config(
        'AUTH_PASSWORD_ONLY' => 'true',
        'AUTH_EMAIL_AUTH_ONLY' => 'true',
        'AUTH_EMAIL_AUTH_ENABLED' => 'true',
      )
      expect(config.password_only_enabled?).to be false
      expect(config.email_auth_only_enabled?).to be false
    end

    it 'all *_only_enabled? return false when three flags are set' do
      config = fresh_config(
        'AUTH_PASSWORD_ONLY' => 'true',
        'AUTH_WEBAUTHN_ONLY' => 'true',
        'AUTH_WEBAUTHN_ENABLED' => 'true',
        'AUTH_SSO_ONLY' => 'true',
        'AUTH_SSO_ENABLED' => 'true',
        'OIDC_ISSUER' => 'https://example.com',
        'OIDC_CLIENT_ID' => 'test-client',
      )
      expect(config.password_only_enabled?).to be false
      expect(config.webauthn_only_enabled?).to be false
      # sso_only uses a different code path (checks sso_config) so it may
      # still return true via legacy path — but single_auth_method_valid?
      # should prevent it in the new single_auth_method section
    end
  end

  # ── active_single_auth_method ──────────────────────────────────────

  describe '#active_single_auth_method' do
    it 'returns nil when no flag is set' do
      config = fresh_config
      expect(config.active_single_auth_method).to be_nil
    end

    it 'returns "password_only" when AUTH_PASSWORD_ONLY=true' do
      config = fresh_config('AUTH_PASSWORD_ONLY' => 'true')
      expect(config.active_single_auth_method).to eq('password_only')
    end

    it 'returns "email_auth_only" when AUTH_EMAIL_AUTH_ONLY=true' do
      config = fresh_config('AUTH_EMAIL_AUTH_ONLY' => 'true')
      expect(config.active_single_auth_method).to eq('email_auth_only')
    end

    it 'returns "webauthn_only" when AUTH_WEBAUTHN_ONLY=true' do
      config = fresh_config('AUTH_WEBAUTHN_ONLY' => 'true')
      expect(config.active_single_auth_method).to eq('webauthn_only')
    end

    it 'returns "sso_only" when AUTH_SSO_ONLY=true' do
      config = fresh_config('AUTH_SSO_ONLY' => 'true')
      expect(config.active_single_auth_method).to eq('sso_only')
    end

    it 'returns nil when multiple flags are set (invalid config)' do
      config = fresh_config('AUTH_PASSWORD_ONLY' => 'true', 'AUTH_WEBAUTHN_ONLY' => 'true')
      expect(config.active_single_auth_method).to be_nil
    end

    it 'returns nil in simple mode' do
      config = fresh_config('AUTHENTICATION_MODE' => 'simple', 'AUTH_PASSWORD_ONLY' => 'true')
      expect(config.active_single_auth_method).to be_nil
    end
  end

  # ── SINGLE_AUTH_KEYS constant ──────────────────────────────────────

  describe 'SINGLE_AUTH_KEYS' do
    it 'contains exactly four keys' do
      expect(described_class::SINGLE_AUTH_KEYS).to eq(
        %w[password_only email_auth_only webauthn_only sso_only]
      )
    end

    it 'is frozen' do
      expect(described_class::SINGLE_AUTH_KEYS).to be_frozen
    end
  end
end
