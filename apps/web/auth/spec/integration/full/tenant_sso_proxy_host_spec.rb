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
# tenant's custom domain, Approximated forwards it as `Apx-Incoming-Host` and
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

  it 'injects the tenant credentials keyed on Apx-Incoming-Host, not the rewritten Host' do
    header 'Host', origin_host
    header 'Apx-Incoming-Host', tenant_domain
    post '/auth/sso/entra'

    location = last_response.headers['Location'].to_s

    expect(location).not_to include('auth_error=sso_not_configured')
    # The tenant id in the authorize URL is the proof that TENANT credentials
    # were injected: the platform Entra credentials in the spec environment
    # carry a different tenant. (client_id is a concealed field — it reads as
    # "[CONCEALED]" here, so it cannot be asserted on.)
    expect(location).to start_with("https://login.microsoftonline.com/#{test_sso_config.tenant_id}/")
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
    header 'Apx-Incoming-Host', tenant_domain
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
