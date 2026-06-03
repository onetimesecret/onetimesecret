# apps/web/auth/spec/integration/full/sso_route_registration_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration
# =============================================================================
#
# Regression test for #3317 — tenant SSO route registration.
#
# When ORGS_SSO_ENABLED=true and no platform SSO env vars are present,
# OmniAuth strategies should register with placeholder credentials so
# that the routes exist (non-404). The OmniAuthTenant hook injects real
# tenant credentials at request time.
#
# Before the fix, missing platform env vars caused strategies to skip
# registration entirely, yielding 404 on all SSO routes even when
# tenant-level SSO was configured.
#
# NOTE: only the positive case (orgs_sso_enabled=true) is tested here.
# The negative case (orgs_sso_enabled=false -> routes are 404) cannot be
# verified in the same RSpec process because route registration is a
# one-shot boot-time operation — the app boots once and @@onetime_booted
# short-circuits subsequent boot_onetime_app calls. The negative path is
# covered at the unit level:
#   apps/web/auth/spec/config/features/omniauth_providers_spec.rb
#
# NOTE: OIDC routes (/auth/sso/oidc) are always registered in the test
# harness because spec_helper sets OIDC_ISSUER and OIDC_CLIENT_ID,
# causing configure_oidc_provider to take the real-creds branch
# regardless of orgs_sso_enabled. The discriminating routes — the ones
# that prove the placeholder-registration fix works — are entra, github,
# and google (no platform creds in the harness).
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   source .env.test && pnpm run test:rspec apps/web/auth/spec/integration/full/sso_route_registration_spec.rb
#
# =============================================================================

# Set ORGS_SSO_ENABLED at file scope (before any boot) so the config
# ERB evaluates it when config.defaults.yaml is loaded. This mirrors
# the pattern in spec_helper.rb lines 29-34 for OIDC env vars.
ENV['ORGS_SSO_ENABLED'] = 'true'

require_relative '../../spec_helper'
require 'webmock/rspec'

RSpec.describe 'SSO route registration with tenant SSO enabled', type: :integration do
  before(:all) do
    boot_onetime_app
  end

  # The OIDC strategy attempts discovery (fetches .well-known) during the
  # request phase. webmock/rspec resets stubs after each example, so these
  # must be registered per-example rather than in before(:all).
  before do
    issuer = ENV.fetch('OIDC_ISSUER', MOCK_OIDC_ISSUER)
    stub_request(:get, "#{issuer}/.well-known/openid-configuration")
      .to_return(
        status: 200,
        body: {
          issuer: issuer,
          authorization_endpoint: "#{issuer}/authorize",
          token_endpoint: "#{issuer}/token",
          userinfo_endpoint: "#{issuer}/userinfo",
          jwks_uri: "#{issuer}/.well-known/jwks.json",
          response_types_supported: %w[code],
          subject_types_supported: %w[public],
          id_token_signing_alg_values_supported: %w[RS256],
          scopes_supported: %w[openid email profile],
        }.to_json,
        headers: { 'Content-Type' => 'application/json' },
      )

    stub_request(:get, "#{issuer}/.well-known/jwks.json")
      .to_return(
        status: 200,
        body: { keys: [] }.to_json,
        headers: { 'Content-Type' => 'application/json' },
      )
  end

  # Use canonical host so DomainStrategy doesn't redirect to
  # sso_not_configured for an unrecognized Host header.
  let(:canonical_host) do
    Onetime::Middleware::DomainStrategy.canonical_domain || 'localhost:3000'
  end

  # OmniAuth provider routes under /auth/sso (POST-only).
  # tenant_only: true marks routes with no platform env vars in the
  # harness — they only exist because of placeholder registration
  # (the #3317 fix) and are the discriminating regression signal.
  sso_routes = {
    '/auth/sso/entra'  => { tenant_only: true },
    '/auth/sso/github' => { tenant_only: true },
    '/auth/sso/google' => { tenant_only: true },
    '/auth/sso/oidc'   => { tenant_only: false },
  }.freeze

  describe 'when ORGS_SSO_ENABLED=true with no platform SSO env vars' do
    sso_routes.each do |route, meta|
      label = meta[:tenant_only] ? 'placeholder registration' : 'platform creds'
      it "POST #{route} is not 404 (#{label})" do
        header 'Host', canonical_host
        post route

        expect(last_response.status).not_to eq(404),
          "#{route} returned 404 (got #{last_response.status}). " \
          "#{meta[:tenant_only] ? 'Placeholder registration from #3317 fix is broken.' : 'Route should be registered via platform credentials.'}"
      end
    end
  end
end
