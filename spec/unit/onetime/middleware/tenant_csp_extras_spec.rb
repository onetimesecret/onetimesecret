# spec/unit/onetime/middleware/tenant_csp_extras_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/middleware/tenant_csp_extras'

# Unit coverage for the per-request tenant CSP form-action widening (#4173).
#
# Host resolution follows the http_origin_options_spec conventions: hosts are
# faked via env['onetime.display_domain'] / env['onetime.domain_strategy']
# (DetectHost + DomainStrategy's published answers), never Host headers. The
# model layer (CustomDomain / SsoConfig) is stubbed — no datastore. The origin
# funnel is the REAL AuthConfig#tenant_idp_origin on an allocated (config-free)
# instance, so the hostile-issuer cases exercise the production origin_from_url
# validation rather than a stub's.
RSpec.describe Onetime::Middleware::TenantCspExtras do
  subject(:middleware) { described_class.new(downstream) }

  let(:downstream_response) { [200, { 'content-type' => 'text/html' }, ['ok']] }
  let(:downstream) { ->(_env) { downstream_response } }

  let(:display_domain) { 'tenant.example.net' }
  let(:domain_id) { 'cd_tenant123' }
  let(:custom_domain) { instance_double(Onetime::CustomDomain, identifier: domain_id) }

  # Real funnel, no config file: AuthConfig#tenant_idp_origin and its private
  # origin_from_url never touch loaded config, so an allocated instance gives
  # the production validation without booting the auth config singleton.
  let(:auth_config) { Onetime::AuthConfig.send(:allocate) }

  let(:extras_key) { Otto::EnvKeys::CSP::EXTRA_DIRECTIVES }

  def build_env(strategy: :custom, display: display_domain, extra: {})
    {
      'onetime.domain_strategy' => strategy,
      'onetime.display_domain' => display,
    }.merge(extra)
  end

  def sso_config_double(provider_type:, issuer: nil, enabled: true)
    instance_double(
      Onetime::CustomDomain::SsoConfig,
      domain_id: domain_id,
      provider_type: provider_type,
      issuer: issuer,
      enabled?: enabled,
    )
  end

  before do
    allow(Onetime).to receive(:auth_config).and_return(auth_config)
  end

  def stub_tenant(config, available: true)
    allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
      .with(display_domain).and_return(custom_domain)
    allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
      .with(domain_id).and_return(config)
    allow(Onetime::CustomDomain::SsoConfig).to receive(:tenant_sso_available_for?)
      .with(domain_id, sso_config: config).and_return(available)
  end

  describe 'non-custom domain strategies' do
    %i[canonical subdomain invalid].each do |strategy|
      it "leaves the env untouched and never reads the datastore for :#{strategy}" do
        expect(Onetime::CustomDomain).not_to receive(:load_by_display_domain)
        env = build_env(strategy: strategy)

        expect(middleware.call(env)).to eq(downstream_response)
        expect(env).not_to have_key(extras_key)
      end
    end

    it 'leaves the env untouched when the strategy is absent (nil)' do
      expect(Onetime::CustomDomain).not_to receive(:load_by_display_domain)
      env = build_env(strategy: nil)

      middleware.call(env)
      expect(env).not_to have_key(extras_key)
    end
  end

  describe 'custom domain without an available tenant SSO config' do
    it 'writes no extras when the display_domain resolves to no CustomDomain' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
        .with(display_domain).and_return(nil)
      env = build_env

      middleware.call(env)
      expect(env).not_to have_key(extras_key)
    end

    it 'writes no extras when the domain has no SsoConfig record' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
        .with(display_domain).and_return(custom_domain)
      allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
        .with(domain_id).and_return(nil)
      env = build_env

      middleware.call(env)
      expect(env).not_to have_key(extras_key)
    end

    it 'writes no extras when the availability ladder rejects (disabled/not permitted)' do
      config = sso_config_double(provider_type: 'oidc', issuer: 'https://idp.example.com')
      stub_tenant(config, available: false)
      env = build_env

      middleware.call(env)
      expect(env).not_to have_key(extras_key)
    end

    it 'writes no extras for an unsupported provider_type (funnel returns nil)' do
      # Belt and suspenders: the availability ladder already fails
      # :unsupported_provider_type closed, but even if it passed, the funnel
      # answers nil for anything outside oidc/entra_id.
      config = sso_config_double(provider_type: 'github')
      stub_tenant(config, available: true)
      env = build_env

      middleware.call(env)
      expect(env).not_to have_key(extras_key)
    end
  end

  describe 'custom domain with available tenant SSO' do
    it 'emits the validated issuer origin for an oidc config' do
      config = sso_config_double(provider_type: 'oidc', issuer: 'https://idp.tenant.example/realms/main')
      stub_tenant(config)
      env = build_env

      middleware.call(env)
      expect(env[extras_key]).to eq('form-action' => ['https://idp.tenant.example'])
    end

    it 'emits the static commercial-cloud origin for an entra_id config' do
      config = sso_config_double(provider_type: 'entra_id')
      stub_tenant(config)
      env = build_env

      middleware.call(env)
      expect(env[extras_key]).to eq('form-action' => ['https://login.microsoftonline.com'])
    end

    it 'does not consult platform SSO state (tenant SSO stands on its own)' do
      # Acceptance intent (b): platform SSO disabled + tenant SSO configured
      # still widens. The allocated auth_config has no loaded config at all,
      # so any sso_enabled?/provider-env consultation would raise — and we
      # pin it explicitly.
      expect(auth_config).not_to receive(:sso_enabled?)
      config = sso_config_double(provider_type: 'oidc', issuer: 'https://idp.tenant.example')
      stub_tenant(config)
      env = build_env

      middleware.call(env)
      expect(env[extras_key]).to eq('form-action' => ['https://idp.tenant.example'])
    end
  end

  describe 'hostile or malformed tenant issuers (real funnel)' do
    # Acceptance intent (c): a hostile issuer is dropped by the funnel and the
    # env carries NO extras key — not an empty hash — and nothing raises.
    [
      ['semicolon injection', 'https://idp.example.com; script-src https://evil.example'],
      ['javascript scheme', 'javascript:alert(1)'],
      ['schemeless', 'idp.example.com'],
      ['blank', ''],
      ['nil issuer', nil],
      ['bare scheme', 'https://'],
    ].each do |label, issuer|
      it "writes no extras for a #{label} issuer" do
        config = sso_config_double(provider_type: 'oidc', issuer: issuer)
        stub_tenant(config)
        env = build_env

        expect { middleware.call(env) }.not_to raise_error
        expect(env).not_to have_key(extras_key)
      end
    end

    it 'strips the path from an issuer rather than rejecting it' do
      # otto's extras channel rejects any token with a path (even a bare
      # trailing slash), so the funnel must emit a clean origin.
      config = sso_config_double(provider_type: 'oidc', issuer: 'https://idp.example.com/')
      stub_tenant(config)
      env = build_env

      middleware.call(env)
      expect(env[extras_key]).to eq('form-action' => ['https://idp.example.com'])
    end
  end

  describe 'datastore failure' do
    it 'warns and proceeds without extras when the domain read raises' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
        .and_raise(StandardError, 'valkey blip')
      expect(OT).to receive(:lw).with(/TenantCspExtras.*tenant\.example\.net.*valkey blip/)
      env = build_env

      expect(middleware.call(env)).to eq(downstream_response)
      expect(env).not_to have_key(extras_key)
    end

    it 'warns and proceeds without extras when the SsoConfig read raises' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
        .with(display_domain).and_return(custom_domain)
      allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
        .and_raise(StandardError, 'valkey blip')
      expect(OT).to receive(:lw)
      env = build_env

      expect(middleware.call(env)).to eq(downstream_response)
      expect(env).not_to have_key(extras_key)
    end
  end

  describe 'pre-existing extras' do
    let(:config) { sso_config_double(provider_type: 'oidc', issuer: 'https://idp.tenant.example') }

    before { stub_tenant(config) }

    it 'merges into an existing extras hash without clobbering other directives' do
      env = build_env(extra: { extras_key => { 'frame-src' => ['https://frames.example'] } })

      middleware.call(env)
      expect(env[extras_key]).to eq(
        'frame-src' => ['https://frames.example'],
        'form-action' => ['https://idp.tenant.example'],
      )
    end

    it 'appends to an existing form-action entry and de-duplicates' do
      env = build_env(extra: {
        extras_key => { 'form-action' => ['https://other.example', 'https://idp.tenant.example'] },
      })

      middleware.call(env)
      expect(env[extras_key]['form-action']).to eq(
        ['https://other.example', 'https://idp.tenant.example'],
      )
    end

    it 'does not mutate the original extras hash in place' do
      original = { 'frame-src' => ['https://frames.example'] }
      env      = build_env(extra: { extras_key => original })

      middleware.call(env)
      expect(original).to eq('frame-src' => ['https://frames.example'])
      expect(env[extras_key]).not_to equal(original)
    end
  end
end
