# apps/web/auth/spec/integration/full/restrict_to_enforcement_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — restrict_to as ACCESS CONTROL (ADR-024 A1/A7, #4139)
# =============================================================================
#
# PR #4130 shipped the display half of domain `restrict_to`: a restricted host
# renders one sign-in method, but the server still ACCEPTED a crafted POST to
# every other method's endpoint. These examples are the crafted POSTs.
#
# The highest-value cases here are not the happy paths — they are:
#
#   1. on a host restricted to ONE method, a direct POST to every OTHER
#      method's endpoint is 404 (A7's reject shape: the route reads as
#      undefined, not forbidden), INCLUDING the secondary endpoints;
#   2. the SSO surface, which is NOT in Rodauth's route_hash — the OmniAuth
#      request phase is middleware-served, so the before_rodauth gate never
#      fires for it and it needs its own gate (config/hooks/omniauth_tenant.rb);
#   3. the ROUTE COVERAGE assertion at the bottom, which fails when a new
#      Rodauth route appears and nobody classified it. A gate that covers the
#      primary POST and misses a ceremony endpoint leaves the gap open while
#      LOOKING closed, which A7 calls worse than no gate at all.
#
# Simple mode is a separate deployment shape and is covered by its sibling,
# spec/integration/simple/restrict_to_enforcement_spec.rb: there POST
# /auth/login is served by Core, not Rodauth, so none of these assertions
# transfer.
#
# REQUIREMENTS:
# - Valkey running on port 2163: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   tests/lanes/run full-pg
#   # or directly:
#   RACK_ENV=test AUTHENTICATION_MODE=full AUTH_DATABASE_URL='sqlite::memory:' \
#     ORGS_SSO_ENABLED=true bundle exec rspec \
#     apps/web/auth/spec/integration/full/restrict_to_enforcement_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require 'rack/test'

RSpec.describe 'restrict_to enforcement — full mode (ADR-024 A1/A7, #4139)', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    boot_onetime_app

    # The custom-domain feature ships OFF in the test config (DOMAINS_ENABLED),
    # and with it off Onetime::Middleware::DomainStrategy short-circuits: every
    # request is classified :canonical and env['onetime.display_domain'] is the
    # canonical host, so a per-domain SigninConfig can never be reached and
    # every example here would pass vacuously against an unrestricted global.
    # Flip the runtime flag (not the env var — the lane env is shared) so the
    # middleware resolves the Host header it was given, and restore after.
    @original_features        = Onetime::Runtime.features
    Onetime::Runtime.features = @original_features.with(domains_enabled: true)
  end

  after(:all) do
    Onetime::Runtime.features = @original_features if @original_features
  end

  let(:run_id) { SecureRandom.hex(6) }

  # A host DomainStrategy will classify as :custom (Chooserator resolves it
  # through CustomDomain.from_display_domain), carrying an *enabled* SigninConfig
  # — the only shape that lets a per-domain restrict_to speak at all.
  def build_restricted_domain(restrict_to)
    owner = Onetime::Customer.new(email: "owner-#{run_id}@test.local")
    owner.save
    org  = Onetime::Organization.create!("RestrictTo Org #{run_id}", owner, 'contact@test.local')
    # tr('_', '-'): an underscore is not legal in a hostname label, and
    # DomainStrategy silently falls back to the canonical host for one
    # (basically_valid? fails), which would make every example here pass
    # vacuously against an unrestricted global.
    host = "restricted-#{restrict_to.tr('_', '-')}-#{run_id}.example.com"

    domain = Onetime::CustomDomain.new(display_domain: host, org_id: org.org_id)
    domain.save
    Onetime::CustomDomain.display_domain_index.put(host, domain.domainid)

    config = Onetime::CustomDomain::SigninConfig.create!(
      domain_id: domain.identifier,
      enabled: true,
      signin_enabled: true,
      restrict_to: restrict_to,
    )

    @fixtures << [org, domain, config, owner, host]
    host
  end

  before { @fixtures = [] }

  after do
    Array(@fixtures).each do |org, domain, _config, owner, host|
      Onetime::CustomDomain::SigninConfig.delete_for_domain!(domain.identifier)
      Onetime::CustomDomain.display_domain_index.remove(host)
      domain.destroy!
      org.destroy!
      owner.destroy!
    rescue StandardError => ex
      warn "[restrict_to spec] cleanup failed for #{host}: #{ex.message}"
    end
  end

  # POST with the CSRF token AND an explicit Host, so DomainStrategy classifies
  # the request as the tenant under test. CSRF matters: check_csrf runs BEFORE
  # before_rodauth, so a token-less POST would be rejected upstream of the gate
  # and the example would pass for the wrong reason.
  def post_as(host, path, params = {})
    header 'Host', host
    csrf_json_post(path, params)
  end

  # A gated route must be byte-identical to an undefined one (A7): same status
  # AND the router's shared ADR-013 body, not a bespoke shape.
  def expect_not_found(response, path)
    expect(response.status).to eq(404),
      "#{path} returned #{response.status}, expected 404 (ADR-024 A7 reject shape). Body: #{response.body[0, 300]}"
    body = JSON.parse(response.body)
    expect(body['error_type']).to eq('NotFound'),
      "#{path} 404'd with a non-router body: #{response.body[0, 300]}"
  end

  # Whether a Rodauth route is mounted at all in this lane's feature set. Used
  # to skip rather than assert vacuously: a feature-disabled route is 404 for
  # reasons that have nothing to do with this gate.
  def route_mounted?(path)
    Auth::Config.route_hash.key?(path)
  end

  # ==========================================================================
  # 1. Crafted POSTs to restricted-away methods
  # ==========================================================================

  describe 'a host restricted to email_auth' do
    let(:host) { build_restricted_domain('email_auth') }

    # Every PASSWORD endpoint, primary and secondary. reset-password-request and
    # reset-password are pre-auth surfaces and go dark with the method (A7's
    # closing paragraph); create-account likewise.
    %w[
      /auth/login
      /auth/create-account
      /auth/reset-password-request
      /auth/reset-password
    ].each do |path|
      it "404s POST #{path}" do
        expect_not_found(post_as(host, path, login: 'nobody@example.com', password: 'x' * 20), path)
      end
    end

    it '404s POST /auth/webauthn-login (passwordless passkey entry point)' do
      skip 'webauthn feature not enabled in this lane' unless route_mounted?('/webauthn-login')

      expect_not_found(post_as(host, '/auth/webauthn-login', login: 'nobody@example.com'), '/auth/webauthn-login')
    end

    it '404s the SSO request phase, which is not in route_hash at all' do
      skip 'SSO routes not registered in this lane' unless Onetime.auth_config.orgs_sso_enabled?

      expect_not_found(post_as(host, '/auth/sso/oidc'), '/auth/sso/oidc')
    end

    it '404s the app-owned SSO linking routes' do
      expect_not_found(post_as(host, '/auth/link-sso', token: 'x', password: 'y'), '/auth/link-sso')
      expect_not_found(post_as(host, '/auth/sso-link-confirm', token: 'x'), '/auth/sso-link-confirm')
    end

    it 'still serves its OWN method (the gate narrows, it does not close)' do
      skip 'email_auth feature not enabled in this lane' unless route_mounted?('/email-auth-request')

      response = post_as(host, '/auth/email-auth-request', login: "nobody-#{run_id}@example.com")
      expect(response.status).not_to eq(404),
        'the permitted method must stay reachable on its own restricted host'
    end
  end

  describe 'a host restricted to sso' do
    let(:host) { build_restricted_domain('sso') }

    it '404s POST /auth/login' do
      expect_not_found(post_as(host, '/auth/login', login: 'nobody@example.com', password: 'x' * 20), '/auth/login')
    end

    it '404s POST /auth/email-auth-request' do
      skip 'email_auth feature not enabled in this lane' unless route_mounted?('/email-auth-request')

      expect_not_found(post_as(host, '/auth/email-auth-request', login: 'nobody@example.com'),
        '/auth/email-auth-request')
    end

    it 'keeps the SSO linking routes reachable (they are an SSO continuation)' do
      response = post_as(host, '/auth/link-sso', token: "missing-#{run_id}", password: 'whatever')
      expect(response.status).not_to eq(404),
        'link-sso is gated on sso, not password: it must work on an sso-restricted host'
    end
  end

  # ==========================================================================
  # 2. Resolution states
  # ==========================================================================

  describe 'the :unavailable state (ADR-024 A3 fail-closed)' do
    # 'webauthn' is not honorable on a custom domain (credentials are rp_id/
    # host-scoped, #4137), so the restriction stands but NOTHING resolves as
    # permitted. The failure mode this guards is widening back to standard mode.
    let(:host) { build_restricted_domain('webauthn') }

    it 'rejects every method, including the one it names' do
      expect_not_found(post_as(host, '/auth/login', login: 'nobody@example.com', password: 'x' * 20), '/auth/login')

      if route_mounted?('/email-auth-request')
        expect_not_found(post_as(host, '/auth/email-auth-request', login: 'nobody@example.com'),
          '/auth/email-auth-request')
      end

      if route_mounted?('/webauthn-login')
        expect_not_found(post_as(host, '/auth/webauthn-login', login: 'nobody@example.com'), '/auth/webauthn-login')
      end
    end
  end

  describe 'the :unrestricted state' do
    let(:canonical_host) do
      Onetime::Middleware::DomainStrategy.canonical_domain || 'localhost:3000'
    end

    it 'rejects nothing — normal sign-in is untouched' do
      skip 'a global restrict_to is configured in this lane' if Onetime.auth_config.restrict_to

      response = post_as(canonical_host, '/auth/login', login: "nobody-#{run_id}@example.com", password: 'x' * 20)
      # 401 (no such account) is the healthy answer here. 404 would mean the
      # gate is rejecting on an unrestricted host.
      expect(response.status).not_to eq(404),
        "the gate must not fire on an unrestricted host (got #{response.status})"
    end

    it 'leaves logout reachable' do
      response = post_as(canonical_host, '/auth/logout')
      expect(response.status).not_to eq(404)
    end
  end

  # ==========================================================================
  # 3. Route coverage — the guard against a new route slipping past the gate
  # ==========================================================================
  #
  # Rodauth freezes route_hash in post_configure, so this reads the LIVE mounted
  # set rather than a transcription of it. A new auth route either gets a
  # sign-in method in GATED_ROUTES or an explicit exemption in UNGATED_ROUTES;
  # defaulting to "allowed" silently is what this exists to prevent.
  #
  describe 'route coverage (ADR-024 A7: every reachable route per method)' do
    let(:gate) { Auth::RestrictTo }

    def mounted_route_names
      Auth::Config.route_hash.values.map { |meth| meth.to_s.delete_prefix('handle_').to_sym }
    end

    it 'classifies every mounted Rodauth route as gated or explicitly exempt' do
      classified   = gate::GATED_ROUTES.keys + gate::UNGATED_ROUTES
      unclassified = mounted_route_names - classified

      expect(unclassified).to be_empty,
        "Rodauth routes with no restrict_to classification: #{unclassified.inspect}\n" \
        'Add each to GATED_ROUTES (with its sign-in method) or UNGATED_ROUTES (with a reason) ' \
        'in apps/web/auth/config/hooks/restrict_to.rb. See ADR-024 A7.'
    end

    it 'reads a non-trivial route set (guards against a vacuous pass)' do
      expect(mounted_route_names).to include(:login, :logout)
      expect(mounted_route_names.size).to be >= 8
    end

    it 'maps every gated route to a valid restrict_to value' do
      values = Onetime::CustomDomain::SigninConfig::RESTRICT_TO_VALUES

      expect(gate::GATED_ROUTES.values.uniq - values).to be_empty
    end

    it 'never gates logout' do
      expect(gate::GATED_ROUTES).not_to have_key(:logout)
    end
  end
end
