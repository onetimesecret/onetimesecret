# spec/unit/onetime/config/auth_config_sso_form_action_origins_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'fileutils'

# Tests for AuthConfig#sso_form_action_origins — the boot-time set of SSO
# identity-provider origins the CSP form-action directive must allow so the
# SSO form POST that 302-redirects to the IdP is not blocked by Chromium.
#
# Provider-derived origins reuse #sso_providers' gate (SSO enabled + required
# env vars present); SSO_FORM_ACTION_ORIGINS is merged in unconditionally.
#
# Strategy mirrors auth_config_spec.rb: write a minimal YAML config to a temp
# file, point ConfigResolver at it, save/restore the touched env, and reset the
# singleton between examples.
#
# Run: pnpm run test:rspec spec/unit/onetime/config/auth_config_sso_form_action_origins_spec.rb
RSpec.describe Onetime::AuthConfig do
  let(:temp_dir) { Dir.mktmpdir('auth_config_sso_origins_test') }
  let(:config_path) { File.join(temp_dir, 'auth.yaml') }

  # Minimal config: full mode, SSO feature gated on AUTH_SSO_ENABLED.
  let(:base_yaml) do
    <<~YAML
      ---
      mode: <%= ENV['AUTHENTICATION_MODE'] || 'full' %>
      simple: {}
      full:
        database_url: "sqlite::memory:"
        features:
          verify_account: false
          sso: <%= ENV['AUTH_SSO_ENABLED'] == 'true' %>
        sso:
          sso_display_name: ''
    YAML
  end

  # ENV families the helper reads — saved and restored around each example.
  let(:env_vars) do
    %w[
      AUTHENTICATION_MODE AUTH_SSO_ENABLED
      OIDC_ISSUER OIDC_CLIENT_ID
      ENTRA_TENANT_ID ENTRA_CLIENT_ID ENTRA_CLIENT_SECRET
      GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET
      GITHUB_CLIENT_ID GITHUB_CLIENT_SECRET
      SSO_FORM_ACTION_ORIGINS
    ]
  end

  before(:each) do
    @saved_env = env_vars.map { |k| [k, ENV[k]] }.to_h
    env_vars.each { |k| ENV.delete(k) }
    File.write(config_path, base_yaml)
    allow(Onetime::Utils::ConfigResolver).to receive(:resolve)
      .with('auth').and_return(config_path)
  end

  after(:each) do
    @saved_env.each do |k, v|
      v.nil? ? ENV.delete(k) : ENV[k] = v
    end
    described_class.instance_variable_set(:@singleton__instance__, nil)
    FileUtils.rm_rf(temp_dir)
  end

  # Reset the singleton, re-render the ERB with the given env, return a fresh
  # instance. AUTH_SSO_ENABLED defaults ON here so provider env vars actually
  # gate a provider (SSO must be enabled for provider origins to appear).
  def fresh_config(sso_enabled: true, **env_overrides)
    ENV['AUTH_SSO_ENABLED'] = 'true' if sso_enabled
    env_overrides.each { |k, v| ENV[k.to_s] = v }
    described_class.instance_variable_set(:@singleton__instance__, nil)
    File.write(config_path, base_yaml)
    described_class.instance
  end

  describe '#sso_form_action_origins' do
    it 'returns [] when nothing is configured' do
      expect(fresh_config.sso_form_action_origins).to eq([])
    end

    # ── per-provider origins ─────────────────────────────────────────

    it 'includes the Google origin when Google is active' do
      config = fresh_config('GOOGLE_CLIENT_ID' => 'id', 'GOOGLE_CLIENT_SECRET' => 'secret')
      expect(config.sso_form_action_origins).to contain_exactly('https://accounts.google.com')
    end

    it 'includes the GitHub origin when GitHub is active' do
      config = fresh_config('GITHUB_CLIENT_ID' => 'id', 'GITHUB_CLIENT_SECRET' => 'secret')
      expect(config.sso_form_action_origins).to contain_exactly('https://github.com')
    end

    it 'includes the (commercial-cloud) Entra origin when Entra is active' do
      config = fresh_config(
        'ENTRA_TENANT_ID' => 'tenant',
        'ENTRA_CLIENT_ID' => 'id',
        'ENTRA_CLIENT_SECRET' => 'secret',
      )
      expect(config.sso_form_action_origins).to contain_exactly('https://login.microsoftonline.com')
    end

    it 'derives the OIDC origin from OIDC_ISSUER' do
      config = fresh_config('OIDC_ISSUER' => 'https://idp.example.com/realms/main', 'OIDC_CLIENT_ID' => 'id')
      expect(config.sso_form_action_origins).to contain_exactly('https://idp.example.com')
    end

    it 'keeps a non-default port in the derived OIDC origin' do
      config = fresh_config('OIDC_ISSUER' => 'https://idp.example.com:8443/x', 'OIDC_CLIENT_ID' => 'id')
      expect(config.sso_form_action_origins).to contain_exactly('https://idp.example.com:8443')
    end

    it 'omits the default 443 port from the derived OIDC origin' do
      config = fresh_config('OIDC_ISSUER' => 'https://idp.example.com:443/x', 'OIDC_CLIENT_ID' => 'id')
      expect(config.sso_form_action_origins).to contain_exactly('https://idp.example.com')
    end

    # Non-TLS http is accepted on purpose: internal OIDC providers commonly run
    # without TLS. Documents that origin_from_url keeps http, only rejecting
    # non-http(s) schemes (see the ftp override case below).
    it 'accepts a plain-http OIDC_ISSUER (internal non-TLS provider)' do
      config = fresh_config('OIDC_ISSUER' => 'http://internal-idp.example.com', 'OIDC_CLIENT_ID' => 'id')
      expect(config.sso_form_action_origins).to contain_exactly('http://internal-idp.example.com')
    end

    # ── malformed / blank OIDC issuer is tolerated ───────────────────

    it 'tolerates a malformed OIDC_ISSUER by skipping it (no raise)' do
      config = fresh_config('OIDC_ISSUER' => 'not a valid uri', 'OIDC_CLIENT_ID' => 'id')
      expect { config.sso_form_action_origins }.not_to raise_error
      expect(config.sso_form_action_origins).to eq([])
    end

    it 'tolerates a schemeless OIDC_ISSUER by skipping it' do
      config = fresh_config('OIDC_ISSUER' => 'idp.example.com', 'OIDC_CLIENT_ID' => 'id')
      expect(config.sso_form_action_origins).to eq([])
    end

    it 'skips OIDC when OIDC_ISSUER is blank (provider does not gate in)' do
      config = fresh_config('OIDC_ISSUER' => '', 'OIDC_CLIENT_ID' => 'id')
      expect(config.sso_form_action_origins).to eq([])
    end

    # URI.parse('https://') sets #host to '' (not nil), so the hostless-guard
    # must treat an empty host as unresolvable — otherwise a degenerate
    # bare-scheme "https://" origin leaks into the CSP form-action directive.
    # The provider still gates in (OIDC_ISSUER is non-empty), so this exercises
    # the origin-derivation guard, not the provider gate.
    it 'skips OIDC (no bare-scheme origin) when OIDC_ISSUER is scheme-only "https://"' do
      config = fresh_config('OIDC_ISSUER' => 'https://', 'OIDC_CLIENT_ID' => 'id')
      expect { config.sso_form_action_origins }.not_to raise_error
      origins = config.sso_form_action_origins
      expect(origins).to eq([])
      expect(origins).not_to include('https://')
    end

    it 'skips OIDC (no bare-scheme origin) when OIDC_ISSUER is hostless "https:///path"' do
      config = fresh_config('OIDC_ISSUER' => 'https:///path', 'OIDC_CLIENT_ID' => 'id')
      expect { config.sso_form_action_origins }.not_to raise_error
      origins = config.sso_form_action_origins
      expect(origins).to eq([])
      expect(origins).not_to include('https://')
    end

    # ── multiple active providers ────────────────────────────────────

    it 'collects origins from every active provider' do
      config = fresh_config(
        'GOOGLE_CLIENT_ID' => 'id', 'GOOGLE_CLIENT_SECRET' => 'secret',
        'GITHUB_CLIENT_ID' => 'id', 'GITHUB_CLIENT_SECRET' => 'secret',
      )
      expect(config.sso_form_action_origins).to contain_exactly(
        'https://accounts.google.com',
        'https://github.com',
      )
    end

    # ── SSO_FORM_ACTION_ORIGINS override ─────────────────────────────

    it 'merges the space-separated SSO_FORM_ACTION_ORIGINS override' do
      config = fresh_config(
        'SSO_FORM_ACTION_ORIGINS' => 'https://login.microsoftonline.us https://sso.example.org',
      )
      expect(config.sso_form_action_origins).to contain_exactly(
        'https://login.microsoftonline.us',
        'https://sso.example.org',
      )
    end

    it 'applies the override even with zero active providers' do
      config = fresh_config(sso_enabled: false, 'SSO_FORM_ACTION_ORIGINS' => 'https://sso.example.org')
      expect(config.sso_form_action_origins).to contain_exactly('https://sso.example.org')
    end

    it 'applies the override even in simple mode (independent of provider gating)' do
      config = fresh_config(
        sso_enabled: false,
        'AUTHENTICATION_MODE' => 'simple',
        'SSO_FORM_ACTION_ORIGINS' => 'https://sso.example.org',
      )
      expect(config.sso_form_action_origins).to contain_exactly('https://sso.example.org')
    end

    it 'de-duplicates when the override repeats a provider-derived origin' do
      config = fresh_config(
        'GOOGLE_CLIENT_ID' => 'id', 'GOOGLE_CLIENT_SECRET' => 'secret',
        'SSO_FORM_ACTION_ORIGINS' => 'https://accounts.google.com',
      )
      expect(config.sso_form_action_origins).to contain_exactly('https://accounts.google.com')
    end

    # ── SSO_FORM_ACTION_ORIGINS override validation ──────────────────
    # Override tokens are routed through origin_from_url and dropped unless they
    # resolve to a clean http(s) origin. Unvalidated tokens would inject into
    # the CSP form-action directive; otto's reject_injection! then 500s every
    # request.

    it 'drops a schemeless override token' do
      config = fresh_config('SSO_FORM_ACTION_ORIGINS' => 'login.microsoftonline.us')
      expect(config.sso_form_action_origins).to eq([])
    end

    # KEY REGRESSION GUARD: a semicolon-injection value must never yield an
    # origin token carrying ';'. URI.parse keeps the trailing ';' on the host,
    # so the host guard in origin_from_url must reject it.
    it 'never emits an origin containing a semicolon from an injection value' do
      config = fresh_config(
        'SSO_FORM_ACTION_ORIGINS' => 'https://idp.example.com; script-src https://evil.example',
      )
      origins = config.sso_form_action_origins
      expect(origins).to all(satisfy { |o| !o.include?(';') })
      expect(origins).not_to include('https://idp.example.com;')
    end

    it 'drops a non-http(s) override token (ftp)' do
      config = fresh_config('SSO_FORM_ACTION_ORIGINS' => 'ftp://files.example.com')
      expect(config.sso_form_action_origins).to eq([])
    end

    # ── SSO feature disabled ─────────────────────────────────────────

    it 'ignores provider env vars when the SSO feature is disabled' do
      config = fresh_config(sso_enabled: false, 'GOOGLE_CLIENT_ID' => 'id', 'GOOGLE_CLIENT_SECRET' => 'secret')
      expect(config.sso_form_action_origins).to eq([])
    end
  end
end
