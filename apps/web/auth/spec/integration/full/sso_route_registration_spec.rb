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
# All four providers (OIDC, Entra, GitHub, Google) register via
# placeholder credentials when ORGS_SSO_ENABLED=true. No platform
# env vars are injected by spec_helper.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   ORGS_SSO_ENABLED=true pnpm run test:rspec apps/web/auth/spec/integration/full/sso_route_registration_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require 'webmock/rspec'

RSpec.describe 'SSO route registration with tenant SSO enabled', type: :integration do
  before(:all) do
    boot_onetime_app
  end

  # The OIDC strategy attempts discovery (fetches .well-known) during the
  # request phase. webmock/rspec resets stubs after each example, so
  # re-stub the placeholder issuer per-example.
  before do
    stub_request(:get, "#{PLACEHOLDER_OIDC_ISSUER}/.well-known/openid-configuration")
      .to_return(
        status: 200,
        body: {
          issuer: PLACEHOLDER_OIDC_ISSUER,
          authorization_endpoint: "#{PLACEHOLDER_OIDC_ISSUER}/authorize",
          token_endpoint: "#{PLACEHOLDER_OIDC_ISSUER}/token",
          userinfo_endpoint: "#{PLACEHOLDER_OIDC_ISSUER}/userinfo",
          jwks_uri: "#{PLACEHOLDER_OIDC_ISSUER}/.well-known/jwks.json",
          response_types_supported: %w[code],
          subject_types_supported: %w[public],
          id_token_signing_alg_values_supported: %w[RS256],
          scopes_supported: %w[openid email profile],
        }.to_json,
        headers: { 'Content-Type' => 'application/json' },
      )

    stub_request(:get, "#{PLACEHOLDER_OIDC_ISSUER}/.well-known/jwks.json")
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
  # All four register via placeholder credentials when ORGS_SSO_ENABLED=true.
  sso_routes = {
    '/auth/sso/entra'  => { tenant_only: true },
    '/auth/sso/github' => { tenant_only: true },
    '/auth/sso/google' => { tenant_only: true },
    '/auth/sso/oidc'   => { tenant_only: true },
  }.freeze

  describe 'when ORGS_SSO_ENABLED=true with no platform SSO env vars' do
    sso_routes.each do |route, _meta|
      it "POST #{route} is not 404 (placeholder registration)" do
        unless Onetime.auth_config.orgs_sso_enabled?
          skip 'ORGS_SSO_ENABLED not set at boot — placeholder routes not registered (run via rake spec:integration:full:agnostic_on_pg)'
        end

        header 'Host', canonical_host
        post route

        expect(last_response.status).not_to eq(404),
          "#{route} returned 404 — placeholder registration from #3317 fix is broken."
      end
    end
  end
end
