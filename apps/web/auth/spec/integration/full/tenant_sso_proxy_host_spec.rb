# apps/web/auth/spec/integration/full/tenant_sso_proxy_host_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full Rack stack)
# =============================================================================
#
# Regression test: tenant SSO must resolve behind a Host-rewriting proxy.
#
# Production topology (Approximated ingress): the browser asks for the
# tenant's custom domain, the edge forwards it as `X-Forwarded-Host` and
# rewrites `Host:` to the origin target. Rack::DetectHost and DomainStrategy
# resolve that into env['onetime.display_domain'], which is what every other
# custom-domain surface reads (HttpOriginOptions #4170, Auth::SigninGate,
# Auth::RestrictTo, TenantSsoResolution).
#
# The omniauth setup hook used to key its CustomDomain lookup on
# `request.host` — the rewritten authority — so the lookup missed and the SSO
# POST answered `302 /signin?auth_error=sso_not_configured` on a domain whose
# very same request classified as `:custom`.
#
# REQUIREMENTS:
# - Valkey running on port 2163: pnpm run test:database:start
# - AUTH_DATABASE_URL set (PostgreSQL)
# - AUTHENTICATION_MODE=full, ORGS_SSO_ENABLED=true
#
# RUN:
#   ORGS_SSO_ENABLED=true pnpm run test:rspec \
#     apps/web/auth/spec/integration/full/tenant_sso_proxy_host_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../support/tenant_test_fixtures'

# :shared_db_state opts these examples out of the per-example Valkey flush.
# The CustomDomain / SsoConfig fixtures come from the 'tenant fixtures' shared
# context's `let!` hooks, and the flush lives in three helpers (this app's
# spec_helper, the core integration_spec_helper, and the top-level
# spec_helper) whose before(:each) ordering relative to a group's `let!` is
# incidental to file load order. Under the full-glob ordering the core flush
# lands AFTER `let!` and wipes the freshly-saved domain, so the SSO POST
# answers `sso_not_configured` for a reason that has nothing to do with host
# resolution — standalone runs never show it. Skipping the flush is
# order-proof here: every example builds fixtures under a unique test_run_id
# and tears them down in `after`. Same fix as domain_sso_join_organization_spec.
RSpec.describe 'Tenant SSO behind a Host-rewriting proxy', :shared_db_state, type: :integration do
  include Rack::Test::Methods
  include_context 'tenant fixtures'

  # The tenant domain has to classify :custom for the resolver to be exercised
  # at all — with the domains axis off DomainStrategy short-circuits, every
  # request classifies :canonical, and the redirect_uri example fails with
  # `got: "127.0.0.1"` on the canonical host. This used to be inherited from
  # the ambient DOMAINS_ENABLED of whatever shell ran the suite.
  include_context 'domains enabled'

  before(:all) { boot_onetime_app }

  # The origin target a Host-rewriting proxy puts in `Host:`.
  let(:origin_host) { canonical_host }

  before do
    unless Onetime.auth_config.orgs_sso_enabled?
      skip 'ORGS_SSO_ENABLED not set at boot — /auth/sso/* routes are not registered'
    end
  end

  # The shared fixtures tear down the SsoConfig only; one example below also
  # opts password sign-in in.
  after { Onetime::CustomDomain::SigninConfig.delete_for_domain!(test_custom_domain.identifier) }

  it 'injects the tenant credentials keyed on X-Forwarded-Host, not the rewritten Host' do
    header 'Host', origin_host
    header 'X-Forwarded-Host', tenant_domain
    post '/auth/sso/entra'

    location = last_response.headers['Location'].to_s

    expect(location).not_to include('auth_error=sso_not_configured')
    # The tenant id in the authorize URL is the proof that TENANT credentials
    # were injected: the platform Entra credentials in the spec environment
    # carry a different tenant. (client_id is a concealed field — it reads as
    # "[CONCEALED]" here, so it cannot be asserted on.)
    expect(location).to start_with("https://login.microsoftonline.com/#{test_sso_config.tenant_id}/")
  end

  # #4579: tenant SSO waiting only on domain verification is refused with a
  # dedicated error on every phase, never handed to the platform fallback.
  context 'when the domain is unverified and password sign-in is opted in' do
    before do
      test_custom_domain.verified = false
      test_custom_domain.save
      # Password sign-in is opted in, so SSO is not this host's only method
      # and restrict_to lets the request reach the tenant ladder. An SSO-only
      # host stops earlier, at the restrict_to gate (next example).
      Onetime::CustomDomain::SigninConfig.create!(
        domain_id: test_custom_domain.identifier,
        enabled: true,
        signin_enabled: true,
        sso_enabled: true,
      )

      # The hook logs other events (e.g. :omniauth_tenant_resolution_start)
      # on every request; let those through so only the refusal is pinned.
      allow(Auth::Logging).to receive(:log_auth_event).and_call_original
    end

    def post_sso_through_proxy
      header 'Host', origin_host
      header 'X-Forwarded-Host', tenant_domain
      post '/auth/sso/entra'
    end

    it 'refuses with sso_domain_unverified before credentials are cached or injected' do
      expect(Auth::Logging).to receive(:log_auth_event).with(
        :omniauth_tenant_domain_unverified,
        level: :warn,
        host: tenant_domain,
        domain_id: test_custom_domain.identifier,
        provider_type: test_sso_config.provider_type,
        pending_tenant_flow_dropped: false,
      ).and_call_original
      expect(Auth::Logging).not_to receive(:log_auth_event).with(:omniauth_tenant_sso_not_enabled, anything)
      expect(Auth::Config::Hooks::OmniAuthTenant).not_to receive(:inject_tenant_credentials)

      post_sso_through_proxy

      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to end_with('/signin?auth_error=sso_domain_unverified')
      expect(last_request.env['onetime.tenant_sso_config']).to be_nil
      expect(last_request.env['rack.session'].to_h.keys.map(&:to_s))
        .not_to include('omniauth_tenant_domain_id', 'omniauth_tenant_host')
    end

    it 'does not fall back to platform SSO even when tenants may fall back' do
      allow(Onetime.auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
      expect(Auth::Config::Hooks::OmniAuthTenant).not_to receive(:handle_missing_tenant_config)

      post_sso_through_proxy

      expect(last_response.headers['Location']).to end_with('/signin?auth_error=sso_domain_unverified')
    end

    # A domain whose sign-in settings withhold SSO is not awaiting
    # verification: verifying it would not turn tenant SSO on, so it keeps
    # the generic ladder refusal it gets once verified.
    it 'keeps the generic refusal when the sign-in settings withhold SSO' do
      Onetime::CustomDomain::SigninConfig.delete_for_domain!(test_custom_domain.identifier)
      Onetime::CustomDomain::SigninConfig.create!(
        domain_id: test_custom_domain.identifier,
        enabled: true,
        signin_enabled: true,
        sso_enabled: false,
      )
      expect(Auth::Logging).to receive(:log_auth_event).with(
        :omniauth_tenant_sso_not_enabled, hash_including(reason: :domain_unverified)
      ).and_call_original
      expect(Auth::Logging).not_to receive(:log_auth_event).with(:omniauth_tenant_domain_unverified, anything)

      post_sso_through_proxy

      expect(last_response.headers['Location']).to include('auth_error=sso_not_configured')
    end
  end

  it 'answers 404 for an SSO-only tenant while its domain is unverified (#4517)' do
    test_custom_domain.verified = false
    test_custom_domain.save

    # No sign-in settings, so SSO is the host's only method. Its 'sso' host
    # pin stays while the domain waits on verification, and the restrict_to
    # gate at the top of the setup hook refuses before the tenant ladder runs.
    allow(Auth::Logging).to receive(:log_auth_event).and_call_original
    expect(Auth::Logging).to receive(:log_auth_event).with(
      :restrict_to_omniauth_rejected, hash_including(host: tenant_domain)
    ).and_call_original
    expect(Auth::Config::Hooks::OmniAuthTenant).not_to receive(:inject_tenant_credentials)

    header 'Host', origin_host
    header 'X-Forwarded-Host', tenant_domain
    post '/auth/sso/entra'

    expect(last_response.status).to eq(404)
  end

  # The callback of a flow started while that SSO-only domain was verified
  # meets the same 404 once verification lapses, and the 404 drops the
  # pending tenant context: markers and the OAuth state / PKCE binding. Left
  # behind, the IdP's answer could still complete the refused flow once the
  # domain verified again.
  it 'drops the pending tenant context when it 404s a callback after verification lapsed' do
    header 'Host', origin_host
    header 'X-Forwarded-Host', tenant_domain
    post '/auth/sso/entra'

    location = last_response.headers['Location'].to_s
    expect(location).to start_with("https://login.microsoftonline.com/#{test_sso_config.tenant_id}/")
    state = CGI.parse(URI.parse(location).query.to_s)['state'].first
    expect(last_request.env['rack.session'].to_h.keys.map(&:to_s))
      .to include('omniauth_tenant_domain_id', 'omniauth_tenant_host', 'omniauth.state')

    test_custom_domain.verified = false
    test_custom_domain.save

    allow(Auth::Logging).to receive(:log_auth_event).and_call_original
    expect(Auth::Logging).to receive(:log_auth_event).with(
      :restrict_to_omniauth_rejected, hash_including(host: tenant_domain, pending_tenant_flow_dropped: true)
    ).and_call_original

    header 'Host', origin_host
    header 'X-Forwarded-Host', tenant_domain
    get '/auth/sso/entra/callback', code: 'idp-code', state: state

    expect(last_response.status).to eq(404)
    expect(last_request.env['rack.session'].to_h.keys.map(&:to_s)).not_to include(
      'omniauth_tenant_domain_id', 'omniauth_tenant_host', *Onetime::SsoProvider::FlowSessionKeys::ALL
    )
  end

  it 'sends the IdP a redirect_uri on the tenant domain, not the origin target' do
    # Resolving the tenant's credentials is only half the flow. The authorize
    # URL carries a redirect_uri built from OmniAuth's `full_host`, which
    # derives from Rack's authority unless overridden — so without the
    # resolver in features/omniauth.rb this names the origin target, and the
    # tenant's IdP rejects it as an unregistered redirect (or honors it and
    # lands the visitor on a host they never authenticated from). Either way
    # `sso_not_configured` would just become a failure one hop later.
    header 'Host', origin_host
    header 'X-Forwarded-Host', tenant_domain
    post '/auth/sso/entra'

    location     = last_response.headers['Location'].to_s
    redirect_uri = CGI.parse(URI.parse(location).query.to_s)['redirect_uri'].first.to_s

    expect(URI.parse(redirect_uri).host).to eq(tenant_domain)
    expect(redirect_uri).to end_with('/auth/sso/entra/callback')
    expect(redirect_uri).not_to include(origin_host)
  end

  it 'still resolves the tenant when the proxy preserves the custom domain in Host' do
    header 'Host', tenant_domain
    post '/auth/sso/entra'

    location = last_response.headers['Location'].to_s

    expect(location).not_to include('auth_error=sso_not_configured')
    expect(location).to start_with("https://login.microsoftonline.com/#{test_sso_config.tenant_id}/")
  end
end
