# spec/unit/onetime/config/auth_config_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'fileutils'

# Systematic tests for AuthConfig, covering all env var mappings and
# the restrict_to single-auth-method override.
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
        <%
          only_flags = [
            ENV['AUTH_PASSWORD_ONLY'] == 'true' ? 'password' : nil,
            ENV['AUTH_EMAIL_AUTH_ONLY'] == 'true' ? 'email_auth' : nil,
            ENV['AUTH_WEBAUTHN_ONLY'] == 'true' ? 'webauthn' : nil,
            ENV['AUTH_SSO_ONLY'] == 'true' ? 'sso' : nil,
          ].compact
          restrict_to = only_flags.length == 1 ? only_flags.first : nil
        %>
        restrict_to: <%= restrict_to %>
        sso:
          sso_display_name: ''
          trust_email_for_linking: <%= ENV['SSO_TRUST_EMAIL_FOR_LINKING'] == 'true' %>
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
      OIDC_ROUTE_NAME ENTRA_ROUTE_NAME GOOGLE_ROUTE_NAME GITHUB_ROUTE_NAME
      SSO_TRUST_EMAIL_FOR_LINKING
      OIDC_TRUST_EMAIL_FOR_LINKING ENTRA_TRUST_EMAIL_FOR_LINKING
      GOOGLE_TRUST_EMAIL_FOR_LINKING GITHUB_TRUST_EMAIL_FOR_LINKING
    ]
  end

  before(:each) do
    # Save existing env
    @saved_env = env_vars.map { |k| [k, ENV[k]] }.to_h

    # Clear env vars to start with a clean slate (CI may set AUTHENTICATION_MODE=simple)
    env_vars.each { |k| ENV.delete(k) }

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

  # ── restrict_to ────────────────────────────────────────────────────

  describe '#restrict_to' do
    it 'returns nil by default' do
      config = fresh_config
      expect(config.restrict_to).to be_nil
    end

    it 'returns "password" when AUTH_PASSWORD_ONLY=true' do
      config = fresh_config('AUTH_PASSWORD_ONLY' => 'true')
      expect(config.restrict_to).to eq('password')
    end

    it 'returns "email_auth" when AUTH_EMAIL_AUTH_ONLY=true' do
      config = fresh_config('AUTH_EMAIL_AUTH_ONLY' => 'true', 'AUTH_EMAIL_AUTH_ENABLED' => 'true')
      expect(config.restrict_to).to eq('email_auth')
    end

    it 'returns "webauthn" when AUTH_WEBAUTHN_ONLY=true' do
      config = fresh_config('AUTH_WEBAUTHN_ONLY' => 'true', 'AUTH_WEBAUTHN_ENABLED' => 'true')
      expect(config.restrict_to).to eq('webauthn')
    end

    it 'returns "sso" when AUTH_SSO_ONLY=true' do
      config = fresh_config('AUTH_SSO_ONLY' => 'true', 'AUTH_SSO_ENABLED' => 'true', 'OIDC_ISSUER' => 'https://example.com', 'OIDC_CLIENT_ID' => 'test')
      expect(config.restrict_to).to eq('sso')
    end

    it 'returns nil in simple mode' do
      config = fresh_config('AUTHENTICATION_MODE' => 'simple', 'AUTH_PASSWORD_ONLY' => 'true')
      expect(config.restrict_to).to be_nil
    end

    it 'returns nil when multiple ENV vars are set (mutual exclusivity)' do
      config = fresh_config('AUTH_PASSWORD_ONLY' => 'true', 'AUTH_SSO_ONLY' => 'true')
      expect(config.restrict_to).to be_nil
    end
  end

  # ── *_only_enabled? convenience predicates ─────────────────────────

  describe '#password_only_enabled?' do
    it 'returns true when restrict_to is password' do
      config = fresh_config('AUTH_PASSWORD_ONLY' => 'true')
      expect(config.password_only_enabled?).to be true
    end

    it 'returns false by default' do
      config = fresh_config
      expect(config.password_only_enabled?).to be false
    end
  end

  describe '#email_auth_only_enabled?' do
    it 'returns true when restrict_to is email_auth and email_auth is enabled' do
      config = fresh_config('AUTH_EMAIL_AUTH_ONLY' => 'true', 'AUTH_EMAIL_AUTH_ENABLED' => 'true')
      expect(config.email_auth_only_enabled?).to be true
    end

    it 'returns false when restrict_to is email_auth but email_auth is disabled' do
      config = fresh_config('AUTH_EMAIL_AUTH_ONLY' => 'true', 'AUTH_EMAIL_AUTH_ENABLED' => 'false')
      expect(config.email_auth_only_enabled?).to be false
    end
  end

  describe '#webauthn_only_enabled?' do
    it 'returns true when restrict_to is webauthn and webauthn is enabled' do
      config = fresh_config('AUTH_WEBAUTHN_ONLY' => 'true', 'AUTH_WEBAUTHN_ENABLED' => 'true')
      expect(config.webauthn_only_enabled?).to be true
    end

    it 'returns false when restrict_to is webauthn but webauthn is disabled' do
      config = fresh_config('AUTH_WEBAUTHN_ONLY' => 'true', 'AUTH_WEBAUTHN_ENABLED' => 'false')
      expect(config.webauthn_only_enabled?).to be false
    end
  end

  describe '#sso_only_enabled?' do
    it 'returns true when restrict_to is sso, SSO enabled, and provider configured' do
      config = fresh_config(
        'AUTH_SSO_ONLY' => 'true',
        'AUTH_SSO_ENABLED' => 'true',
        'OIDC_ISSUER' => 'https://example.com',
        'OIDC_CLIENT_ID' => 'test-client',
      )
      expect(config.sso_only_enabled?).to be true
    end

    it 'returns false when restrict_to is sso but SSO disabled' do
      config = fresh_config('AUTH_SSO_ONLY' => 'true', 'AUTH_SSO_ENABLED' => 'false')
      expect(config.sso_only_enabled?).to be false
    end

    it 'returns false when restrict_to is sso, SSO enabled, but no provider' do
      ENV.delete('OIDC_ISSUER')
      ENV.delete('OIDC_CLIENT_ID')
      config = fresh_config('AUTH_SSO_ONLY' => 'true', 'AUTH_SSO_ENABLED' => 'true')
      expect(config.sso_only_enabled?).to be false
    end
  end

  # ── trust_email_for_linking? (#3836 email-linking escape hatch) ─────
  #
  # Keys on the ROUTE NAME (the value omniauth_provider returns), reverse-
  # mapped to the provider's env prefix via the registry. Each provider has
  # its own *_TRUST_EMAIL_FOR_LINKING var; a global SSO_TRUST_EMAIL_FOR_LINKING
  # is the deprecated single-OIDC / catch-all fallback.

  describe '#trust_email_for_linking?' do
    # Route name -> per-provider trust var. Verifies the reverse-mapping
    # (entra_id != entra != ENTRA) resolves to the right env var for all four.
    {
      'oidc' => 'OIDC_TRUST_EMAIL_FOR_LINKING',
      'entra' => 'ENTRA_TRUST_EMAIL_FOR_LINKING',
      'google' => 'GOOGLE_TRUST_EMAIL_FOR_LINKING',
      'github' => 'GITHUB_TRUST_EMAIL_FOR_LINKING',
    }.each do |route_name, trust_var|
      context "for the '#{route_name}' route" do
        it "defaults to false when #{trust_var} is unset" do
          config = fresh_config
          expect(config.trust_email_for_linking?(route_name)).to be false
        end

        it "returns true when #{trust_var}=true" do
          config = fresh_config(trust_var => 'true')
          expect(config.trust_email_for_linking?(route_name)).to be true
        end

        it "returns false when #{trust_var}=false" do
          config = fresh_config(trust_var => 'false')
          expect(config.trust_email_for_linking?(route_name)).to be false
        end

        it "is unaffected by another provider's trust var" do
          other = (%w[OIDC ENTRA GOOGLE GITHUB] - [trust_var.split('_').first]).first
          config = fresh_config("#{other}_TRUST_EMAIL_FOR_LINKING" => 'true')
          expect(config.trust_email_for_linking?(route_name)).to be false
        end
      end
    end

    it 'accepts a symbol route name (omniauth_provider returns a symbol)' do
      config = fresh_config('ENTRA_TRUST_EMAIL_FOR_LINKING' => 'true')
      expect(config.trust_email_for_linking?(:entra)).to be true
    end

    it 'reverse-maps a custom route name from *_ROUTE_NAME' do
      config = fresh_config(
        'OIDC_ROUTE_NAME' => 'zitadel',
        'OIDC_TRUST_EMAIL_FOR_LINKING' => 'true',
      )
      expect(config.trust_email_for_linking?('zitadel')).to be true
      # The default 'oidc' route name no longer maps to the OIDC definition.
      expect(config.trust_email_for_linking?('oidc')).to be false
    end

    it 'returns false for an unknown route name with no global flag' do
      config = fresh_config
      expect(config.trust_email_for_linking?('unknown')).to be false
    end

    context 'global SSO_TRUST_EMAIL_FOR_LINKING fallback' do
      it 'applies to every provider when no per-provider var is set' do
        config = fresh_config('SSO_TRUST_EMAIL_FOR_LINKING' => 'true')
        expect(config.trust_email_for_linking?('oidc')).to be true
        expect(config.trust_email_for_linking?('entra')).to be true
        expect(config.trust_email_for_linking?('google')).to be true
        expect(config.trust_email_for_linking?('github')).to be true
      end

      it 'is overridden by an explicit per-provider var (per-provider wins)' do
        config = fresh_config(
          'SSO_TRUST_EMAIL_FOR_LINKING' => 'true',
          'ENTRA_TRUST_EMAIL_FOR_LINKING' => 'false',
        )
        # entra explicitly opts out; the others still inherit the global true.
        expect(config.trust_email_for_linking?('entra')).to be false
        expect(config.trust_email_for_linking?('oidc')).to be true
      end
    end
  end

  describe '#trust_email_for_linking_enabled?' do
    it 'returns false when no trust flag is set (clean install)' do
      config = fresh_config
      expect(config.trust_email_for_linking_enabled?).to be false
    end

    it 'returns true when the global flag is set' do
      config = fresh_config('SSO_TRUST_EMAIL_FOR_LINKING' => 'true')
      expect(config.trust_email_for_linking_enabled?).to be true
    end

    it 'returns true when any per-provider flag is set' do
      config = fresh_config('GITHUB_TRUST_EMAIL_FOR_LINKING' => 'true')
      expect(config.trust_email_for_linking_enabled?).to be true
    end

    it 'returns false when a per-provider flag is explicitly false' do
      config = fresh_config('GITHUB_TRUST_EMAIL_FOR_LINKING' => 'false')
      expect(config.trust_email_for_linking_enabled?).to be false
    end

    # Truth-table (b) — global true, all provider vars absent → true — is
    # already covered by 'returns true when the global flag is set' above.

    it 'returns false when the global flag is set but every provider opts out' do
      # Truth-table (a) — the #3844 fix. A global true with EVERY provider
      # explicitly false means linking is disabled everywhere; the boot guard
      # must NOT warn about a flag that has no effect.
      config = fresh_config(
        'SSO_TRUST_EMAIL_FOR_LINKING' => 'true',
        'OIDC_TRUST_EMAIL_FOR_LINKING' => 'false',
        'ENTRA_TRUST_EMAIL_FOR_LINKING' => 'false',
        'GOOGLE_TRUST_EMAIL_FOR_LINKING' => 'false',
        'GITHUB_TRUST_EMAIL_FOR_LINKING' => 'false',
      )
      expect(config.trust_email_for_linking_enabled?).to be false
    end

    it 'returns true when the global flag is set and only some providers opt out' do
      # Guards against over-correcting the fix: providers WITHOUT an explicit
      # var still inherit the global true, so the flag remains effectively on.
      config = fresh_config(
        'SSO_TRUST_EMAIL_FOR_LINKING' => 'true',
        'GITHUB_TRUST_EMAIL_FOR_LINKING' => 'false',
      )
      expect(config.trust_email_for_linking_enabled?).to be true
    end

    it 'returns true for a trusted provider on a custom route name' do
      # Truth-table (c): a custom *_ROUTE_NAME must still round-trip through
      # provider_definition_for_route back to its own trust var.
      config = fresh_config(
        'OIDC_ROUTE_NAME' => 'zitadel',
        'OIDC_TRUST_EMAIL_FOR_LINKING' => 'true',
      )
      expect(config.trust_email_for_linking_enabled?).to be true
    end
  end

  # ── RESTRICT_TO_VALUES constant ────────────────────────────────────

  describe 'RESTRICT_TO_VALUES' do
    it 'contains the four valid restriction values' do
      expect(described_class::RESTRICT_TO_VALUES).to eq(
        %w[password email_auth webauthn sso]
      )
    end

    it 'is frozen' do
      expect(described_class::RESTRICT_TO_VALUES).to be_frozen
    end
  end

  # ── Missing config file (graceful degradation) ─────────────────────

  describe 'when config file is missing' do
    before do
      allow(Onetime::Utils::ConfigResolver).to receive(:resolve)
        .with('auth').and_return('/nonexistent/auth.yaml')
      described_class.instance_variable_set(:@singleton__instance__, nil)
    end

    subject(:config) { described_class.instance }

    it 'does not raise on instantiation' do
      expect { config }.not_to raise_error
    end

    it 'reports as not configured' do
      expect(config.configured?).to be false
    end

    it 'returns nil for mode' do
      expect(config.mode).to be_nil
    end

    it 'returns false for full_enabled?' do
      expect(config.full_enabled?).to be false
    end

    it 'returns false for simple_enabled?' do
      expect(config.simple_enabled?).to be false
    end

    it 'returns empty hash for full' do
      expect(config.full).to eq({})
    end

    it 'returns empty hash for simple' do
      expect(config.simple).to eq({})
    end
  end
end
