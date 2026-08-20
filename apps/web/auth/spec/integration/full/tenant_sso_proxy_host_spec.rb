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

RSpec.describe 'Tenant SSO behind a Host-rewriting proxy', type: :integration do
  include Rack::Test::Methods
  include_context 'tenant fixtures'

  before(:all) do
    boot_onetime_app

    # DomainStrategy's class-level config is normally populated when the
    # middleware is first instantiated; the canonical_host let below reads it
    # before any request has been made.
    Onetime::Middleware::DomainStrategy.initialize_from_config(
      OT.conf&.dig('features', 'domains') || {},
    )
  end

  # The origin target a Host-rewriting proxy puts in `Host:`.
  let(:origin_host) do
    Onetime::Middleware::DomainStrategy.canonical_domain || 'localhost:3000'
  end

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

  it 'still resolves the tenant when the proxy preserves the custom domain in Host' do
    header 'Host', tenant_domain
    post '/auth/sso/entra'

    location = last_response.headers['Location'].to_s

    expect(location).not_to include('auth_error=sso_not_configured')
    expect(location).to start_with("https://login.microsoftonline.com/#{test_sso_config.tenant_id}/")
  end
end
