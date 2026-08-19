# spec/unit/onetime/middleware/tenant_csp_extras_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/middleware/tenant_csp_extras'

# Unit coverage for the per-request tenant CSP form-action widening (#4173).
#
# The middleware resolves on the way OUT: it calls downstream first and only
# consults the datastore when the response is HTML, CSP is enabled, and a
# display_domain was published. Host resolution follows the
# http_origin_options_spec conventions: hosts are faked via
# env['onetime.display_domain'] (DetectHost + DomainStrategy's published
# answer), never Host headers — and deliberately NOT via
# env['onetime.domain_strategy'], which the middleware ignores (see the
# :invalid-strategy case below). The model layer (CustomDomain / SsoConfig)
# is stubbed — no datastore. The origin funnel is the REAL
# AuthConfig#tenant_idp_origin on an allocated (config-free) instance, so the
# available-SSO cases exercise the production origin_from_url validation
# rather than a stub's; the full hostile-issuer table lives in
# auth_config_sso_form_action_origins_spec, which owns the funnel.
RSpec.describe Onetime::Middleware::TenantCspExtras do
  subject(:middleware) { described_class.new(downstream) }

  let(:response_headers) { { 'content-type' => 'text/html; charset=utf-8' } }
  let(:downstream_response) { [200, response_headers, ['ok']] }
  let(:downstream) { ->(_env) { downstream_response } }

  let(:display_domain) { 'tenant.example.net' }
  let(:domain_id) { 'cd_tenant123' }

  # Real funnel, no config file: AuthConfig#tenant_idp_origin and its private
  # helpers never touch loaded config, so an allocated instance gives the
  # production validation without booting the auth config singleton.
  let(:auth_config) { Onetime::AuthConfig.send(:allocate) }

  let(:extras_key) { Otto::EnvKeys::CSP::EXTRA_DIRECTIVES }
  let(:csp_enabled) { true }

  def build_env(display: display_domain, extra: {})
    {
      'onetime.domain_strategy' => :custom,
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
    allow(OT).to receive(:conf).and_return(
      'site' => { 'security' => { 'csp' => { 'enabled' => csp_enabled } } },
    )
    allow(Onetime).to receive(:auth_config).and_return(auth_config)
  end

  def stub_tenant(config, available: true)
    allow(Onetime::CustomDomain).to receive(:resolve_domain_id)
      .with(display_domain).and_return(domain_id)
    allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
      .with(domain_id).and_return(config)
    allow(Onetime::CustomDomain::SsoConfig).to receive(:tenant_sso_available_for?)
      .with(domain_id, sso_config: config).and_return(available)
  end

  describe 'pre-read guards (no datastore work unless the response can carry a CSP)' do
    it 'never reads the datastore when CSP is disabled' do
      allow(OT).to receive(:conf).and_return(
        'site' => { 'security' => { 'csp' => { 'enabled' => false } } },
      )
      expect(Onetime::CustomDomain).not_to receive(:resolve_domain_id)
      env = build_env

      expect(middleware.call(env)).to eq(downstream_response)
      expect(env).not_to have_key(extras_key)
    end

    it 'never reads the datastore for a non-HTML response (JSON)' do
      response_headers['content-type'] = 'application/json'
      expect(Onetime::CustomDomain).not_to receive(:resolve_domain_id)
      env = build_env

      expect(middleware.call(env)).to eq(downstream_response)
      expect(env).not_to have_key(extras_key)
    end

    it 'reads a canonically-cased Content-Type (case-insensitive, like otto and RequestSetup)' do
      response_headers.delete('content-type')
      response_headers['Content-Type'] = 'application/json'
      expect(Onetime::CustomDomain).not_to receive(:resolve_domain_id)
      env = build_env

      middleware.call(env)
      expect(env).not_to have_key(extras_key)
    end

    it 'treats an ABSENT Content-Type as HTML (RequestSetup defaults it to text/html downstream)' do
      # RequestSetup#ensure_content_type (the OUTER layer) fills in text/html
      # after this middleware returns, so a header-less response WILL be
      # emitted with a CSP — the widening must stay in lockstep with it.
      response_headers.clear
      config = sso_config_double(provider_type: 'oidc', issuer: 'https://idp.tenant.example')
      stub_tenant(config)
      env = build_env

      middleware.call(env)
      expect(env[extras_key]).to eq('form-action' => ['https://idp.tenant.example'])
    end

    it 'never reads the datastore when no display_domain was published' do
      expect(Onetime::CustomDomain).not_to receive(:resolve_domain_id)
      env = build_env(display: nil)

      middleware.call(env)
      expect(env).not_to have_key(extras_key)
    end
  end

  describe 'domain strategy independence (#4173 skew fix)' do
    it 'still widens on an :invalid strategy when the display_domain resolves' do
      # DomainStrategy answers :invalid when ITS datastore read blips, while
      # display_domain survives — and the SSO button's serializer
      # (ConfigSerializer#resolve_tenant_sso_config) keys on display_domain
      # alone, so the button still renders. A strategy gate here would skip
      # the widening for exactly that page: the original #4173 symptom.
      config = sso_config_double(provider_type: 'oidc', issuer: 'https://idp.tenant.example')
      stub_tenant(config)
      env = build_env(extra: { 'onetime.domain_strategy' => :invalid })

      middleware.call(env)
      expect(env[extras_key]).to eq('form-action' => ['https://idp.tenant.example'])
    end

    it 'writes no extras for a canonical-host display_domain (index resolves no domain_id)' do
      allow(Onetime::CustomDomain).to receive(:resolve_domain_id)
        .with(display_domain).and_return(nil)
      env = build_env(extra: { 'onetime.domain_strategy' => :canonical })

      middleware.call(env)
      expect(env).not_to have_key(extras_key)
    end
  end

  describe 'domain resolution' do
    it 'resolves via the index-only read, downcased (resolve_domain_id does not normalize)' do
      config = sso_config_double(provider_type: 'oidc', issuer: 'https://idp.tenant.example')
      stub_tenant(config)
      env = build_env(display: 'Tenant.Example.NET')

      middleware.call(env)
      expect(Onetime::CustomDomain).to have_received(:resolve_domain_id).with('tenant.example.net')
      expect(env[extras_key]).to eq('form-action' => ['https://idp.tenant.example'])
    end
  end

  describe 'custom domain without an available tenant SSO config' do
    it 'writes no extras when the domain has no SsoConfig record' do
      allow(Onetime::CustomDomain).to receive(:resolve_domain_id)
        .with(display_domain).and_return(domain_id)
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

    it 'writes no extras (and does not raise) for an unknown provider_type' do
      # Availability is force-passed to prove the funnel independently fails
      # closed: a provider_type with no PROVIDER_ROUTE_MAP entry answers nil,
      # never raises — the guard for a future route-map/registry drift.
      config = sso_config_double(provider_type: 'saml_future')
      stub_tenant(config, available: true)
      env = build_env

      expect { middleware.call(env) }.not_to raise_error
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

    it 'writes no extras (not an empty hash) when the funnel rejects a hostile issuer' do
      # ONE representative funnel-rejection case; the full hostile-issuer
      # table (injection, schemes, blanks, paths) lives in
      # auth_config_sso_form_action_origins_spec, which owns the funnel.
      config = sso_config_double(
        provider_type: 'oidc',
        issuer: 'https://idp.example.com; script-src https://evil.example',
      )
      stub_tenant(config)
      # The operator-facing warning for this state is pinned in the
      # misconfiguration-warning group below; silenced here.
      allow(OT).to receive(:lw)
      env = build_env

      expect { middleware.call(env) }.not_to raise_error
      expect(env).not_to have_key(extras_key)
    end
  end

  describe 'misconfiguration warning (available tenant SSO, rejected origin)' do
    # The nil-return path out of AuthConfig#tenant_idp_origin used to be
    # completely silent: the availability ladder renders the SSO button, the
    # widening never happens, and the only symptom is a blocked redirect in
    # the visitor's browser console. One warning fires for exactly that
    # combination — available + non-blank tenant-supplied origin source +
    # rejected origin — and for no other nil path.
    it 'warns when an available oidc config has a non-blank issuer the funnel rejects' do
      config = sso_config_double(
        provider_type: 'oidc',
        issuer: 'https://idp.example.com; script-src https://evil.example',
      )
      stub_tenant(config)
      expect(OT).to receive(:lw)
        .with(/TenantCspExtras.*tenant\.example\.net.*provider_type="oidc".*not widened/m)
      env = build_env

      middleware.call(env)
      expect(env).not_to have_key(extras_key)
    end

    it 'warns once per normalized domain across repeated HTML requests' do
      config = sso_config_double(
        provider_type: 'oidc',
        issuer: 'https://idp.example.com; script-src https://evil.example',
      )
      stub_tenant(config)
      expect(OT).to receive(:lw).once

      middleware.call(build_env)
      middleware.call(build_env(display: 'Tenant.Example.NET'))
    end

    it 'truncates and escapes the tenant-supplied issuer in the warning' do
      # The issuer is attacker-influenced: it must not reach the log verbatim
      # or unbounded, and control characters must be escaped so a crafted
      # value cannot forge extra log lines.
      hostile = "https://idp.example.com\nWARN forged log line #{'a' * 300}"
      config  = sso_config_double(provider_type: 'oidc', issuer: hostile)
      stub_tenant(config)
      messages = []
      allow(OT).to receive(:lw) { |message| messages << message }

      middleware.call(build_env)

      expect(messages.size).to eq(1)
      message = messages.first
      expect(message).to include('https://idp.example.com')
      expect(message).not_to include(hostile)
      expect(message).not_to include("\n")
      expect(message).to include('\n')
      expect(message).to include('...')
      expect(message.length).to be < 300
    end

    it 'stays silent when the issuer validates (widening happens)' do
      config = sso_config_double(provider_type: 'oidc', issuer: 'https://idp.tenant.example')
      stub_tenant(config)
      expect(OT).not_to receive(:lw)
      env = build_env

      middleware.call(env)
      expect(env[extras_key]).to eq('form-action' => ['https://idp.tenant.example'])
    end

    it 'stays silent when the domain has no SsoConfig record' do
      allow(Onetime::CustomDomain).to receive(:resolve_domain_id)
        .with(display_domain).and_return(domain_id)
      allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
        .with(domain_id).and_return(nil)
      expect(OT).not_to receive(:lw)
      env = build_env

      middleware.call(env)
      expect(env).not_to have_key(extras_key)
    end

    it 'stays silent when the availability ladder rejects (no button is rendered either)' do
      config = sso_config_double(
        provider_type: 'oidc',
        issuer: 'https://idp.example.com; script-src https://evil.example',
      )
      stub_tenant(config, available: false)
      expect(OT).not_to receive(:lw)
      env = build_env

      middleware.call(env)
      expect(env).not_to have_key(extras_key)
    end

    it 'stays silent for a blank issuer (unconfigured, not misconfigured)' do
      config = sso_config_double(provider_type: 'oidc', issuer: '   ')
      stub_tenant(config)
      expect(OT).not_to receive(:lw)
      env = build_env

      middleware.call(env)
      expect(env).not_to have_key(extras_key)
    end

    it 'stays silent for a non-issuer-derived provider type (registry drift, not tenant data)' do
      # entra_id's origin comes from the static registry definition, so a nil
      # there is route-map/registry drift an operator cannot fix by editing
      # the tenant record — naming the tenant's issuer would mislabel it.
      config = sso_config_double(provider_type: 'saml_future', issuer: 'https://idp.example.com')
      stub_tenant(config)
      expect(OT).not_to receive(:lw)
      env = build_env

      middleware.call(env)
      expect(env).not_to have_key(extras_key)
    end
  end

  describe 'datastore failure' do
    # The domain-index read (resolve_domain_id) swallows datastore errors
    # internally and returns nil, so the middleware's rescue is reachable
    # only from the SsoConfig/availability reads and origin derivation.
    it 'warns and proceeds without extras when the SsoConfig read raises' do
      allow(Onetime::CustomDomain).to receive(:resolve_domain_id)
        .with(display_domain).and_return(domain_id)
      allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
        .and_raise(StandardError, 'valkey blip')
      expect(OT).to receive(:lw).with(/TenantCspExtras.*tenant\.example\.net.*valkey blip/)
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

    it 'splits a String-form entry before appending (otto reads a String as a token LIST)' do
      # Array('https://a https://b') would wrap the list as ONE token, which
      # otto's whitespace FORBIDDEN_CHARS check then drops wholesale —
      # silently vanishing the other layer's origins.
      env = build_env(extra: {
        extras_key => { 'form-action' => 'https://a.example https://b.example' },
      })

      middleware.call(env)
      expect(env[extras_key]['form-action']).to eq(
        ['https://a.example', 'https://b.example', 'https://idp.tenant.example'],
      )
    end

    it "normalizes a 'form_action'-spelled key instead of writing a colliding sibling" do
      # Otto normalizes directive keys (to_s.strip.downcase.tr('_', '-')), so
      # 'form_action' and 'form-action' collide INSIDE otto where one side
      # would silently win; normalizing before the merge keeps both.
      env = build_env(extra: {
        extras_key => { :form_action => ['https://other.example'] },
      })

      middleware.call(env)
      expect(env[extras_key]).to eq(
        'form-action' => ['https://other.example', 'https://idp.tenant.example'],
      )
    end

    it 'concatenates token lists when keys collapse under normalization' do
      env = build_env(extra: {
        extras_key => {
          'Form-Action' => ['https://a.example'],
          'form_action' => 'https://b.example',
        },
      })

      middleware.call(env)
      expect(env[extras_key]).to eq(
        'form-action' => ['https://a.example', 'https://b.example', 'https://idp.tenant.example'],
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
